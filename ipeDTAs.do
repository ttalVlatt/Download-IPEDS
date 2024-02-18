**----------------------------------------------------------------------------**
**
** [PROJ: ipeDTAs: Automagically download labeled .dta IPEDS files]
** [FILE: ipeDTAs.do]
** [INIT: February 14 2024]
** [AUTH: Matt Capaldi] @ttalVlatt
** [CRED: Benjamin T. Skinner] @btskinner
**
**----------------------------------------------------------------------------**

/* 

This project is an extension of @btskinner's downloadipeds.R to automagically
download labeled .dta versions of IPEDS data files, which can then be used for
analysis in Stata or R (via haven)

First, this script first calls DWI.R, which downloads and prepares IPEDS data.
If you are not running a version of Stata locally installed on your computer, it
will be easier to first run DWI.R separately to download and set up the files,
then run this script with lines 40 and 42 commented out

Second, this script loops through these prepared files running (modified) .do 
scripts from IPEDS to make labeled .dta copies of the data in the 
labeled-data sub-folder

Note: Part of this process replaces original data files with _rv revised
versions if available, the resulting file uses the original name without _rv

To Run

0. You will need an installation of R which can be downloaded from https://cran.rstudio.com

1. Un-comment the files you want from ipeds-file-list.txt (remove ## from name)
	Hint: in many text editors you can hold alt to drag a cursor to multiple
	lines at once, so you can comment/un-comment many lines at once

2. Ensure the working directory is set to the main DLI folder

3. Hit "Do"

*/

**----------------------------------------------------------------------------**
** Select the Files to Download
**----------------------------------------------------------------------------**

local selected_files ///
"HD2022" ///
"IC2022" ///
"IC2022_AY" ///
"IC2022_PY" ///
"IC2022_CAMPUSES" ///
"EFFY2018"

**----------------------------------------------------------------------------**
** Create Folders
**----------------------------------------------------------------------------**

* Make folders if they don't exist
capture confirm file "raw-data"
if _rc mkdir "raw-data"
capture confirm file "unzip-data"
if _rc mkdir "unzip-data"
capture confirm file "dta-data"
if _rc mkdir "dta-data"
capture confirm file "raw-dofiles"
if _rc mkdir "raw-dofiles"
capture confirm file "unzip-dofiles"
if _rc mkdir "unzip-dofiles"
capture confirm file "fixed-dofiles"
if _rc mkdir "fixed-dofiles"
capture confirm file "raw-dictionary"
if _rc mkdir "raw-dictionary"
capture confirm file "unzip-dictionary"
if _rc mkdir "unzip-dictionary"
* h/t https://www.statalist.org/forums/forum/general-stata-discussion/general/1344241-check-if-directory-exists-before-running-mkdir

**----------------------------------------------------------------------------**
** Loops to Download the .zip Files
**----------------------------------------------------------------------------**

* Loop through getting the .csv files
foreach file in "`selected_files'" {

	if(!fileexists("raw-data/`file'_Data_Stata.zip")) {
	
    di "Downloading: `file' .csv File"
    copy "https://nces.ed.gov/ipeds/datacenter/data/`file'_Data_Stata.zip" "raw-data/`file'_Data_Stata.zip"
	
	* Wait for three seconds between files
	sleep 3000
	
	}
	
}

* Loop through getting the .do files
foreach file in "`selected_files'" {

	if(!fileexists("raw-dofiles/`file'_Stata.zip")) {
	
    di "Downloading: `file' .do File"
    copy "https://nces.ed.gov/ipeds/datacenter/data/`file'_Stata.zip" "raw-dofiles/`file'_Stata.zip"
	
	* Wait for three seconds between files
	sleep 3000
	
	}
	
}

* Loop through getting the dictionary files
foreach file in "`selected_files'" {

	if(!fileexists("raw-dictionary/`file'_Dict.zip")) {
	
    di "Downloading: `file' Dictionary"
    copy "https://nces.ed.gov/ipeds/datacenter/data/`file'_Dict.zip" "raw-dictionary/`file'_Dict.zip"
	
	* Wait for three seconds between files
	sleep 3000
	
	}
	
}

**----------------------------------------------------------------------------**
** Loops to Unzip the .zip Files
**----------------------------------------------------------------------------**

* .csv Files
cd raw-data

local files_list: dir . files "*.zip"

cd ../unzip-data

foreach file in `files_list' {
	
	unzipfile ../raw-data/`file'
	
}

* .do Files
cd ../raw-dofiles

local files_list: dir . files "*.zip"

cd ../unzip-dofiles

foreach file in `files_list' {
	
	unzipfile ../raw-dofiles/`file'
	
}

* Dictionary Files
cd ../raw-dictionary

local files_list: dir . files "*.zip"

cd ../unzip-dictionary

foreach file in `files_list' {
	
	unzipfile ../raw-dictionary/`file'
	
}

cd ..

**----------------------------------------------------------------------------**
** If _rv file exists replace original data with it
**----------------------------------------------------------------------------**

cd unzip-data

local files_list: dir . files "*_rv*.csv"

foreach file in `files_list' {
	
	local rv_name: di "`file'"
	local og_name: subinstr local rv_name "_rv" ""
	
	di "Replacing `og_name' with `rv_name'"
	
	erase "`og_name'"
	
	_renamefile "`rv_name'" "`og_name'"
	
}

* https://www.statalist.org/forums/forum/general-stata-discussion/general/1422353-trouble-renaming-files-using-renfiles-command

cd ..

**----------------------------------------------------------------------------**
** Fix the .do files Using pystata
**----------------------------------------------------------------------------**

cd unzip-dofiles

python

import re
import os

files_list = os.listdir()

for i in files_list:

	print("Fixing " + i)
	
	file = open(i, "r", encoding='latin-1')
	do_file = file.readlines()
	
	file_name = re.sub(".do", "", i)
	
	## Replace insheet line with updated file path

	pattern = re.compile("^\s?insheet")
	new_insheet = "".join(['insheet using "../unzip-data/', file_name, '_data_stata.csv", comma clear \n'])

	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			do_file[index] = new_insheet
	
	
	## Remove problematic lines by index
		
	index_to_delete = []
	
	## Index lines that save data
	pattern = re.compile("^\s?save")

	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			index_to_delete.append(index)
	
	## Index lines that tab data
	pattern = re.compile("^\s?tab")

	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			index_to_delete.append(index)
			
	## Index lines that summarize data
	pattern = re.compile("^\s?summarize")

	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			index_to_delete.append(index)
			
	## Identify problematic attempts to label strings
	
	label_string_vars = []

	## Variable that start with anything but a digit or - sign
	pattern = re.compile("^label define\s+\w+\s+[^0-9-].*")	
	
	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			label_string_vars.append(line.split(" ")[2])

	## Variables that start with a digit or minus sign, but end in letter (e.g., 11A)
	pattern = re.compile("^label define\s+\w+\s+\b-?\d+[A-Za-z]\b.*")	
	
	for index, line in enumerate(do_file):
		if re.match(pattern, line):
			label_string_vars.append(line.split(" ")[2])
			
	## Get unique list of vars
	label_string_vars = list(set(label_string_vars))
	
	print(len(set(label_string_vars)))
	
	## Prevents loop activating when no problematic vars, as regex becomes ".*"
	if len(set(label_string_vars)) > 0:
	
		## Create regex pattern from the list of variables
		pattern = "|".join(label_string_vars)
		## h/t https://stackoverflow.com/questions/21292552/equivalent-of-paste-r-to-python
		pattern = ".*" + pattern
		pattern = re.compile(pattern)
	
		for index, line in enumerate(do_file):
			if re.match(pattern, line):
				index_to_delete.append(index)
				
		print("String var loop activated for " + i)
	
	
	## Get unique indexes
	index_to_delete = list(set(index_to_delete))
	
	print("# Lines to Delete: " + str(len(index_to_delete)))

	print("# Lines in .do file: " + str(len(do_file)))	

	## Delete problematic lines by index
	for index in sorted(index_to_delete, reverse = True):
		del do_file[index]
	
	print("# Lines in cut .do file: " + str(len(do_file)))
	
	## Write the updated .do file
	
	fixed_file_name = "../fixed-dofiles/" + i
	fixed_file = open(fixed_file_name, "w", encoding='latin-1')
	file.seek(0) ## Move lines editor back to start, h/t ChatGPT
	fixed_file.writelines(do_file)
	
end
	

	
	
	

end



		
		

		

		

		
		

	
print(len(index_to_delete))
	
	



print(label_string_vars)



print(label_string_vars)

# python
# label_string_vars = ["a", "c", "b"]


print(pattern)
	








end

print(max(index_to_delete))
		
print(len(do_file))		

print(sorted(index_to_delete, reverse = True))

## Write the updated .do file
##fixed_file = open("../fixed-dofiles/ic2022_campuses.do", "w", encoding='latin-1')
##file.seek(0) # Move lines edutor back to start, h/t ChatGPT
#file.truncate() ## Remove old content, h/t ChatGPT
##fixed_file.writelines(do_file)



/* BELOW HERE WORKS

** Install rscript package, more info at https://github.com/reifjulian/rscript
net install rscript, from("https://raw.githubusercontent.com/reifjulian/rscript/master")
** Source R script
rscript using DLI.R
** Optional: specify path to R with , rpath() but rscript checks usual locations

** Development Opportunity: Stata-ify the R code to run entirely within Stata

** Clear any data currently stored
clear	

** Change directory to .do files folder
cd unzip-stata-dofiles

** List the downloaded .do files
local files_list: dir . files "*.do"

di `files_list'

foreach file in `files_list' {
	
    ** Take file name as a "string" as convert .do to .dta
    local do_name: di "`file'"
	di "`do_name'"
	local dta_name : subinstr local do_name ".do" ".dta"
	di "`dta_name'"
	** h/t https://stackoverflow.com/questions/17388874/how-to-get-rid-of-the-extensions-in-stata-loop
	
	** Only run .do file to label if the file doesn't exist
	if(!fileexists("../labeled-data/`dta_name'")) {
	
		** Run the modified .do file from IPEDS
		do `file'
	
		** Write the labaled data file as .dta
		save ../labeled-data/`dta_name', replace
	
	}
	
	** Clear the data from memory before next loop
	clear

}
	
cd ..

** Clear any data currently stored
clear

** Delete downloaded files (optional: un-comment to run and save storage space)
*shell rm -r stata-data
*shell rm -r stata-dofiles
*shell rm -r unzip-stata-data
*shell rm -r unzip-stata-dofiles

** If on Windows without Unix shell, use "shell rmdir stata-data" etc.
