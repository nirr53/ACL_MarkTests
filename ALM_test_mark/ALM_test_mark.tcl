
#Mark_ALM_test.bat <path to TestSet> <test name> <additional parameters to mark> <result> <conditions>


# The  <parameters to mark> and <conditions> are list: param1 val1 par2 val2 ....
#1)      When you  passed list of "conditions" and "mark" arguments  you need the quotation only if an element contains spaces 
#2)      As quotation sign you can use single quotation symbol ( ' )  or curly braces ( { } )

#Like 
#set cond [list Regression Yes]
#set a_parameter {Delete Me} ; set par_value 12
#set mark [list $a_parameter  $par_value Tester audiomatic {Draft Run} Y]
#exec d:/Temp/ALM_IPP_update.bat Test1/DeleteMeFolder1/DeleteMeTestSet1 DeleteMeTest1 $mark Passed $cond

# Configuration params
#===============
array set AlmConfigPars [list \
	DEBUG 1 \
	logfilename {\\netapp1\Sip-qa\ALM_test_mark\ALM_test_mark.log} \
	logfilesizemax 500000000 \
	ALM_project IP_Phone \
	config_file ALM_test_mark.cfg \
	create_test_path {} \
	create_testplan_folder 0 \
	test_team "" \
	create_test_in_testset 0 \
	result_map [list {Warning Passed} {Skipped "No Run"} {Waiting "No Run"}] \
]
#set AlmConfigPars(SQL_Database) default_ip_phone_db
#set AlmConfigPars(ALM_user) qa-cmbu
#set AlmConfigPars(ALM_password) Qacmbu202
set AlmConfigPars(SQL_Database) {Unknown SQL_Database}
set AlmConfigPars(ALM_user) {Unknown ALM_user}
set AlmConfigPars(ALM_password) {Unknown ALM_password}

foreach {par val} [array get AlmConfigPars] {set $par $val}

if {[regexp -nocase {^(\?|h|help)$} [string trim [lindex $argv 0] {-/ }]]} {
	puts {
	Arguments: path test mark result condition [parameters]
	'path' - path to TestSet
	'test' - test name
	'mark' - list of fields to mark: <field1> <value1> ... <fieldN> <ValueN>
	'condition' - list fields to check (<field1> <value1> ...) - only test that have appropriate values in specified fields will be marked
	'parameters' (optional) - configuration parameters (see below), you can set the parameters in 'ALM_test_mark.cfg' file also
	}
	foreach par [array names AlmConfigPars] {
		puts "\t\t'$par' - default value '$AlmConfigPars($par)'"
	}
	exit 0
}

#set sender_name almupdate
#set s2_service_men alex.rodikov
#set mail_server_ip 10.1.1.60
set SQL_Server aclsql01\\aclalm 
set SQL_User td
set SQL_Pass tdtdtd
set REST_URL  http://aclalmqa:8080/qcbin
set REST_URL_project $REST_URL/rest/domains/DEFAULT/projects
set ResultStrings [list Passed Failed N/A Blocked "No Run" "Not Completed"]

set script [info script]
set script_dir  [file dirname $script]
if [catch {package require tclodbc} er] {
	if ![file isdirectory [set dir [file normalize ./lib/TCLODBC]]] {
		set dir "[info nameofexecutable]/lib/TCLODBC"
	}
	source "$dir/PKGINDEX.TCL"
	package require tclodbc
}
package require http

# SQL/REST fields mapping
#====================
# format: set FieldsMap(<name string>,<table prefix>) <SQL column neme without table prefix>
# table prefixis: TS  - tests in TestPlan, TC - test instance in TestLab, RN - run of test instance
# == !!! Not USED now!!! (will be needed for REST?) - extructed from SQL table
array set FieldsMap [list \
	Regression,TS		USER_04 \
	"Delete Me,RN"		USER_01 \
	"Delete Me,TC"		USER_01 \
	"Draft Run,RN"		DRAFT	\
]

# Procs
#==========
rename puts puts_original
proc puts args {
	global logfilename logfilesizemax
	if [catch "puts_original $args" er] {
		puts_original stderr $er
		return
	}
	if {$logfilename==""} {return}
	global LogF
	
	if {[file writable $logfilename] && [file size $logfilename]>$logfilesizemax} {
		catch {close $LogF}
		catch {unset LogF}
		catch {file delete -force $logfilename}
	}
	if {![info exists LogF] || [lsearch [file channels] $LogF]==-1} {
		catch {unset LogF}
		catch {set LogF [open $logfilename a]} er
		#puts_original "open log file ($logfilename): '$er'"
	}
	if {![info exists LogF] || [lsearch [file channels] $LogF]==-1} {return}
	foreach par [list stderr stdout] {
		if {[set ind [lsearch $args $par]]!=-1} {
			set args [lreplace $args $ind $ind]
		}
	}
	if {[set argsL [llength $args]]==1 || ($argsL==2 && [lindex $args 0]=="-nonewline")} {
		if {$argsL==1} {set args [linsert $args 0 $LogF]}
		if {$argsL==2} {set args [linsert $args 1 $LogF]}
		set args [lreplace $args end end "[get_time]:(pid [pid], host [info host]) [lindex $args end]"]
		if [catch "puts_original $args ; flush $LogF" er] {
			puts_original stderr $er
		}
	}
}
proc DEBUG args {
	if {$::DEBUG==1} {
		puts "DEBUG: [lindex $args 0]"
	} else {
		# Print in file in any case
		global LogF logfilename
		catch {
			if {$logfilename==""} {return}
			puts_original $LogF "DEBUG: [lindex $args 0]"
		}
	}
}
rename error error_original
proc error args {
	set str "ERROR! [lindex $args 0]"
	puts $str
	#set $::errorInfo {}
	exit 1
}
proc get_time {} {return [clock format [clock seconds] -format "%Y %D %H:%M:%S"]}
proc s2cl_sql_connect {} {
	uplevel #0 {
		package require tclodbc 
		if {[info command dbcommand]!=""} {
			if [catch {dbcommand tables ""} er] {
				puts "Warning! 'dbcommand' exists but connection to DB is dead, Try to refresh the connection"
				catch {dbcommand disconnect} er
				puts $er
			} else {
				# OK! Connection exists and active
				return
			}		
		}
		#s2cl_GetGlobParams
		
		if [catch {database connect dbcommand "DRIVER=SQL Server;SERVER=$SQL_Server;DATABASE=$SQL_Database;UID=$SQL_User;Pwd=$SQL_Pass"} er] {
			error "Connection to database failed!, error: '$er'"
		}
		#DEBUG "OK! SuccessfulLy connected to SQL DB"
	}
}
proc rest_connect {} {
	uplevel {
		if {[info exists REST_QCSession] && [info exists REST_token]} {return}
		
		package require http
		#global REST_token REST_URL ALM_user ALM_password
		set url $REST_URL/authentication-point/alm-authenticate
		set body "
		<alm-authentication>
			<user>$ALM_user</user>
			<password>$ALM_password</password>
		</alm-authentication>"
		
		#::rest::post url query ?config? ?body?
		#::rest::post $url {} $config $body
		set hl [http::geturl $url -method POST -query $body -type application/xml]
		#puts [http::code $hl]
		set httpdata [http::data $hl]
		if {![string match "*200 OK*" [::http::code $hl]]} {
			DEBUG $httpdata
			regsub -all -- {<.+?>} $httpdata {} httpdata
			error "fail to initiate REST session! http response:\n [string trim $httpdata]"
		}
		DEBUG "REST connect:\n[set $hl\(meta)]"
		set REST_token [lindex [set $hl\(meta)] [lsearch -regexp [set $hl\(meta)] {^LWSSO_COOKIE_KEY=}]]
		http::cleanup $hl
		set hl [http::geturl $REST_URL/rest/site-session -method POST -headers [list Cookie $REST_token]]
		set httpdata [http::data $hl]
		if {![string match "*200 OK*" [::http::code $hl]]} {
			DEBUG $httpdata
			regsub -all -- {<.+?>} $httpdata {} httpdata
			error "fail to initiate REST session! http response:\n [string trim $httpdata]"
		}
		DEBUG "REST Get session ID:\n[set $hl\(meta)]"
		set REST_QCSession [lindex [set $hl\(meta)] [lsearch -regexp [set $hl\(meta)] {^QCSession=+}]]
		http::cleanup $hl
		if {$REST_QCSession=="" || $REST_token==""} {
			error "Fail to extract REST_QCSession or REST_token"
		}
	}
}
proc rest_update {tcInst} {
	uplevel {
		rest_connect
		set url $REST_URL_project/$ALM_project/test-instances/$tcInst
		DEBUG "REST get data for test instance '$tcInst' (GET url '$url')"
		set hl [http::geturl $url -method GET -headers [list Cookie $REST_token] -type application/xml]
		DEBUG [http::data $hl]
		http::cleanup $hl
		set fields_list "
			<Field Name=\"status\">
			  <Value>$result</Value>
			</Field>
		"
		#  Will be done by SQL
		foreach {par val} $mark {
			if [info exists FieldsMap($par,TC)] {
				regsub -all -- {_} [string tolower $FieldsMap($par,TC)] {-} par
				DEBUG "Build rest command, add: <Field Name=\"$par\"> <Value>$val</Value>"
				append fields_list "
					<Field Name=\"$par\">
					  <Value>$val</Value>
					</Field>
				"
			}
		}
		#http::geturl $url -method GET -headers [list Cookie $REST_token]
		set body "
		<Entity Type=\"test-instance\">
		  <Fields>
		  $fields_list
		  </Fields>
		</Entity>"
		
		set hl [http::geturl $url -method PUT -headers [list Cookie $REST_token] -query $body -type application/xml]
		if {![string match "*200 OK*" [::http::code $hl]]} {
			# Return old status 
			if {$cur_status!="Blocked" && $cur_status==$result} {
				dbcommand "UPDATE TESTCYCL SET TC_STATUS='$cur_status' WHERE TC_TESTCYCL_ID='$tcInst'"
			}
			error "fail to update '$test' result ($result) by REST, http response:\n [http::data $hl]"
		}
		DEBUG "REST query result:\n[http::data $hl]"
		http::cleanup $hl
		DEBUG " Successfully marked '$test' in '$path', result '$result'"
		# Get last RUN line
		if {[set Run_ID [lindex [lsort -integer [dbcommand "SELECT RN_RUN_ID FROM RUN WHERE RN_TESTCYCL_ID='$tcInst'"]] end]]==""} {
			error "cannot get RUN ID status for TC_TESTCYCL_ID='$tcInst' (test '$test')"
		}
		DEBUG " found RUN ID '$Run_ID' (TC_TESTCYCL_ID='$tcInst')"
		array unset par_set
		set tbl_list [list TESTCYCL RUN] ; set pref_list [list TC RN]
		if {$create_test_path!=""} {
			lappend tbl_list TEST ; lappend pref_list TS
		}

		foreach table $tbl_list pref $pref_list {
			set cmd {}
			foreach {par val} $mark {
				if [info exists FieldsMap($par,$pref)] {
					append cmd ,$pref\_$FieldsMap($par,$pref)='$val'
					set par_set($par) 1
				}
			}
			if {$cmd!=""} {
				if {$table=="RUN"} {
					set dbcmd "UPDATE $table SET [string trim $cmd ,] WHERE RN_RUN_ID='$Run_ID'"
				} elseif {$table=="TESTCYCL"} {
					set dbcmd "UPDATE $table SET [string trim $cmd ,] WHERE TC_TESTCYCL_ID='$tcInst'"
				} elseif {$table=="TEST"} {
					set dbcmd "UPDATE $table SET [string trim $cmd ,] WHERE TS_TEST_ID='$TestID'"
				}
				DEBUG $dbcmd
				if {[dbcommand $dbcmd]==""} {
					error "failed to update '$table' table parameters ($cmd)"
				}
			}
		}
		foreach {par val} $mark {
			if ![info exists par_set($par)] {
				error "parameter '$par' is not found in any SQL table and cannot be marked!"
			}
		}
	}
}
proc rest_close {} {
	uplevel {
		set url $REST_URL/rest/site-session
		set hl [http::geturl $url -method DELETE -headers [list Cookie $REST_token Cookie $REST_QCSession]]
		if {![string match "*200 OK*" [::http::code $hl]]} {
			puts "ERROR! fail to close REST session (http response:\n [http::data $hl]"
		}
		DEBUG "REST close session:\n[http::data $hl]" ; http::cleanup $hl
		foreach tk [list  REST_QCSession REST_token] {
			if {[info exists $tk]} {unset $tk}
		}
	}
}

#===============================
#    The script 
#===============================

foreach [list path test mark result condition parameters] $argv {break}
if {[set ind [lsearch $parameters config_file]]!=-1} {
	catch {source [lindex $parameters [incr ind]]}
} elseif [file readable $config_file] {
	source $config_file
}
DEBUG "[info script] $argv"
if {$path!=""} {
	DEBUG "\t== ALM update: test '$test' in '$path' TestSet, result '$result' (params to mark \"$mark\", conditions \"$condition\")"
} else {
	DEBUG "\t== ALM update (empty TestSet): test '$test', (conditions \"$condition\")"
}
set test_original $test
regsub {^\[\d+\]} $test {} test

foreach {par val} $parameters {set $par $val}
DEBUG " argv = '$argv'"
foreach par [list path test mark result condition parameters] {
	set $par [string trim [set $par] \"]
	DEBUG "$par='[set $par]'"
}
if {$path!=""} {
	if {[lsearch $ResultStrings $result]==-1} {
		if {[set map [lsearch -inline $result_map [list $result *]]]==""} {
			error "Wrong result string ($result) - should be one of '$ResultStrings'"
		}
		if {[lsearch $ResultStrings [set result [lindex $map end]]]==-1} {
			error "Wrong result mapping ($map) - should be one of '$ResultStrings'"
		}
		DEBUG "Set new result string ($result)"
	}
}

foreach el [list mark condition parameters] {
	if ![llength [set $el]] {continue}
	regsub -all {'(.+?)'} [set $el] \{\\1\} $el
	# treat <par>=<val>, format
	set newL [list]
	foreach parval [split [set $el] ,] {
		if {[regexp {^(.+)=\s*(.+)$} [string trim $parval] -> par val]} {
			lappend newL $par $val
		}
	}
	if {[llength $newL]} {
		DEBUG "($el) <par>=<val> format detected"
		set $el $newL
	}
	if [info exists default_$el] {
		foreach {par val} [set default_$el] {
			if {[lsearch [set $el] $par]==-1} {lappend $el $par $val}
		}
	}
	if {[expr [llength [set $el]]%2]!=0} {
		error "Wrong format of '$el' argument - not even number of the elements (counted [llength [set $el]], $el='[set $el]')"
	}
	
	DEBUG "Processed '$el' = '[set $el]'"
}
if [file readable $config_file] {
	set body [read [set fh [open $config_file r]]]
	close $fh
	regsub -all -line {^\s*#.*$} $body {} body
	regsub -all {\n\n|\r\n\r\n} $body \n body
	DEBUG "[file tail $config_file] body:\n[string repeat - 40]\n[string trim $body]"
	source $config_file
}
foreach {par val} $parameters {
	DEBUG "Set parameter '$par' == '$val'"
	set $par $val
}

DEBUG " current directory: '$script_dir'"
set TesLabFoldersList [split [string trim $path "/ "] /]
s2cl_sql_connect
set TestID [dbcommand "SELECT TS_TEST_ID FROM TEST WHERE TS_NAME='$test'"]
DEBUG " Found '$TestID' ([llength $TestID] instances) of '$test' in TestPlan"
if {$path==""} {
	# Works only for TP_7_2 project (mandatory fields are different)?
	puts "Warning! The TestSet path is empty string - is it used for test creation only?"
	if {$TestID=="" && ($create_test_path=="" || $test_team=="")} {
		error "To create new tests you have to set TestPlan folder by 'create_test_path' parameter and QA team by 'test_team' parmeter"
	}
} elseif {[llength $TesLabFoldersList]<2} {
	error "The test plan path should be at least two folders separated by '/' (you entered '$path')"
}
#if {[lsearch $ResultStrings $result]==-1} {
#	error "Wrong test result ($result). Must be one of '$ResultStrings'. Cannot mark '$test'"
#}

set newTestCreated 0
if {$TestID==""} {
	set newTestCreated 1
	if {$create_test_path==""} {
		set fh [open ALM_test_mark_missed.csv a+]
		seek $fh 0
		set testList [read $fh]
		if ![regexp -line "^$test\," $testList] {
			puts $fh "$test,$result"
		} else {
			DEBUG "Test ($test) already added to missed tests file"
		}
		close $fh
		error "test '$test' doesn't exist in TestPlan!"
	}
	puts "test '$test' doesn't exist in TestPlan - a new test will be created in '$create_test_path'"
	
	set parentID 2 ;# Root folder
	set parentName "Subject"
	foreach folder [split $create_test_path /] {
		if {$folder==""} {error "You enter empty folder in the test path ($create_test_path)"}
		set folderID_byParent [dbcommand "SELECT AL_ITEM_ID FROM ALL_LISTS WHERE AL_FATHER_ID='$parentID' AND AL_DESCRIPTION='$folder'"]
		if {$folderID_byParent==""} {
			set str "fail to find folder '$folder' with appropriate parent  (ID=$parentID, name = '$parentName')"
			if {$create_testplan_folder!=0} {
				puts $str
				puts "The new folder '$folder' will be created with parentID='$parentID'"
				rest_connect
				set url $REST_URL_project/$ALM_project/test-folders
				set body "
					<Entity Type=\"test-folder\">
						<Fields>
							<Field Name=\"parent-id\">
								<Value>$parentID</Value>
							</Field>
							<Field Name=\"name\">
								<Value>$folder</Value>
							</Field>
							<Field Name=\"description\">
								<Value>Created automatically</Value>
							</Field>
						</Fields>
					</Entity>
				"		
				set hl [http::geturl $url -method POST -headers [list Cookie $REST_token] -query $body -type application/xml]
				if {![string match "*201 Created*" [::http::code $hl]]} {
					error "fail to create TestPlan folder '$folder' (parent folder '$parentName) by REST, http response:\n [http::data $hl]"
				}
				DEBUG "REST POST result:\n[http::data $hl]"
				if ![regexp -nocase {<Field Name="id">\s*<Value>\s*([0-9]+)\s*</Value>\s*</Field>} [::http::data $hl] -> id] {
					error "failed to get folder id!!"
				}
				http::cleanup $hl
				set parentID $id
				set parentName $folder
			} else {
				error $str
			}
		} elseif {[llength $folderID_byParent]>1} {
			error "found >1 folders '$folder' (full path '$create_test_path')"
		} else {
			DEBUG "TestPlan folder '$folder' successfully found (parent folder '$parentName', id $parentID)"
			set parentID $folderID_byParent
			set parentName $folder
		}
	}
	DEBUG "TestPlan folder '$create_test_path' successfully found"
	rest_connect
	set url $REST_URL_project/$ALM_project/tests
	set body "
		<Entity Type=\"test\">
			<Fields>
				<Field Name=\"user-03\">
					<Value>$test_team</Value>
				</Field>
				<Field Name=\"name\">
					<Value>$test</Value>
				</Field>
				<Field Name=\"description\">
					<Value>Created automatically</Value>
				</Field>
				<Field Name=\"parent-id\">
					<Value>$parentID</Value>
				</Field>
				<Field Name = \"subtype-id\">
					<Value>LR-SCENARIO</Value>
				</Field>
			</Fields>
		</Entity>
	"		
	set hl [http::geturl $url -method POST -headers [list Cookie $REST_token] -query $body -type application/xml]
	if {![string match "*201 Created*" [::http::code $hl]]} {
		puts "REST command:\n $body"
		error "fail to create '$test' (folder $create_test_path) by REST, http response:\n [http::data $hl]"
	}
	DEBUG "REST POST result:\n[http::data $hl]"
	if ![regexp -nocase {<Field Name="id">\s*<Value>\s*([0-9]+)\s*</Value>\s*</Field>} [::http::data $hl] -> TestID] {
		error "failed to get newtest id!!"
	}
	http::cleanup $hl
} elseif {$path==""} {
	error "Test ($test) already exists in TestPlan - will not be inserted"
}
if {$path==""} {
	puts "OK! Completed (TestSet path is empty - test will not be marked in TestLab)"
	exit 0
}
#Verify that 'mark' and 'condition' parameters are exists
array unset FieldsMap
foreach el [list mark condition] {
	foreach {par val} [set $el] {
		if {$el=="condition"} {
			set dbcmd "SELECT SF_COLUMN_NAME,SF_IS_SYSTEM,SF_TABLE_NAME FROM SYSTEM_FIELD WHERE (SF_TABLE_NAME='TESTCYCL' OR SF_TABLE_NAME='TEST') AND SF_USER_LABEL='$par'"
		} else {
			if {$create_test_path!=""} {
				set dbcmd "SELECT SF_COLUMN_NAME,SF_IS_SYSTEM,SF_TABLE_NAME FROM SYSTEM_FIELD WHERE (SF_TABLE_NAME='TESTCYCL' OR SF_TABLE_NAME='RUN' OR SF_TABLE_NAME='TEST') AND SF_USER_LABEL='$par'"				
			} else {
				set dbcmd "SELECT SF_COLUMN_NAME,SF_IS_SYSTEM,SF_TABLE_NAME FROM SYSTEM_FIELD WHERE (SF_TABLE_NAME='TESTCYCL' OR SF_TABLE_NAME='RUN') AND SF_USER_LABEL='$par'"
			}
		}
		#DEBUG $dbcmd
		if {[set res [dbcommand $dbcmd]]==""} {
			error "$el parameter '$par' doesn't exists!"
		}
		foreach lll $res {
			foreach {table_par system table} $lll {break}
			switch $table {
				RUN {set table RN}
				TESTCYCL {set table TC}
				TEST {set table TS}
				default {
					error "condition parameter '$par' doesn't exists! (wrong table '$table')"
				}
			}
			regsub {^tc_} [string tolower $table_par] {} table_par
			regsub {^rn_} [string tolower $table_par] {} table_par
			regsub {^ts_} [string tolower $table_par] {} table_par
			set FieldsMap($par,$table) $table_par
			DEBUG "FieldsMap($par,$table) = '$table_par'"
		}
	}
}

set parentID 0 ;# Root folder
set parentName "Root folder"
set TestSetName [lindex $TesLabFoldersList end]
set TesLabFoldersList [lrange $TesLabFoldersList 0 end-1]
foreach folder $TesLabFoldersList {
	if {$folder==""} { 
		error "You enter empty folder in the path ($path)"
	}
	set folderID_byParent [dbcommand "SELECT CF_ITEM_ID FROM CYCL_FOLD WHERE CF_FATHER_ID='$parentID' AND CF_ITEM_NAME='$folder'"]
	if {$folderID_byParent==""} {
		error "fail to find folder '$folder' with appropriate parent  (ID=$parentID, name = '$parentName')"
	}
	if {[llength $folderID_byParent]>1} {
		error "found >1 folders '$folder' (full path '$path')"
	}
	set parentID $folderID_byParent
	set parentName $folder
}
#DEBUG " Found path ($path) - last folder ID '$parentID'"
set TestSetID [dbcommand "SELECT CY_CYCLE_ID FROM CYCLE WHERE CY_FOLDER_ID='$parentID' AND CY_CYCLE='$TestSetName'"]
if {$TestSetID==""} {
	error "fail to find TestSet '$TestSetName' in '$path' path"
}
DEBUG "OK! found TestSet '$TestSetName' (TestSetID=$TestSetID) in '[join $TesLabFoldersList /]' folder"
#return $TestSetID

set foundTC 0
set tcInst {}
foreach tid $TestID {
	# Check there is at least one test in TestSet
	if {[set tci [dbcommand "SELECT TC_TESTCYCL_ID FROM TESTCYCL WHERE TC_CYCLE_ID=$TestSetID AND TC_TEST_ID='$tid'"]]!=""} {
		incr foundTC
		set tcInst $tci
	}
}
if {$foundTC>1} {
	puts "Warning! found several test instances ($foundTC) with the same name in the test set"
}
if {$tcInst==""} {
	set str "test '$test' doesn't exists in '$path' TestSet!"
	if {!$create_test_in_testset} {
		error "$str (create_test_in_testset=$create_test_in_testset)"
	}
	puts "$str - insert the test in the TestSet"
} else {
	DEBUG "Found Test instances: '$tcInst'"
}
set newTestSetInstance 0
if {$tcInst==""} {
	set newTestSetInstance 1
	#Insert test in TestSet
	rest_connect
	set url $REST_URL_project/$ALM_project/test-instances
	set body "
		<Entity Type=\"test-instance\">
			<Fields>
				<Field Name=\"test-id\">
					<Value>$TestID</Value>
				</Field>
				<Field Name=\"test-order\">
					<Value>1</Value>
				</Field>
				<Field Name=\"status\">
					<Value>No Run</Value>
				</Field>
				<Field Name=\"subtype-id\">
					<Value>hp.qc.test-instance.MANUAL</Value>
				</Field>
				<Field Name=\"cycle-id\">
					<Value>$TestSetID</Value>
				</Field>
			</Fields>
		</Entity>
	"		
	set hl [http::geturl $url -method POST -headers [list Cookie $REST_token] -query $body -type application/xml]
	if {![string match "*201 Created*" [::http::code $hl]]} {
		error "fail to insert test '$test' (test id '$TestID') in TestSet by REST, http response:\n [http::data $hl]"
	}
	DEBUG "REST POST result:\n[http::data $hl]"
	if ![regexp -nocase {<Field Name="id">\s*<Value>\s*([0-9]+)\s*</Value>\s*</Field>} [::http::data $hl] -> TI_id] {
		error "failed to get new test instance id!!"
	}
	DEBUG "== Got TI_id=='$TI_id'"
	http::cleanup $hl	
}
set cond_cmd {}
array set update_cmd [list TS "" TC ""]
foreach {par val} $condition {
	DEBUG "Set '$par='$val' condition parameters"
	set par_found 0
	foreach el [array names FieldsMap $par,*] {
		set table [lindex [split $el ,] end]
		if {$table=="TC" || $table=="TS"} {
			if {$newTestCreated && $table=="TS"} {
				append update_cmd(TS) ",\[$table\_$FieldsMap($el)\]='$val'"				
			}
			if {$newTestSetInstance && $table=="TC"} {
				append update_cmd(TC) ",\[$table\_$FieldsMap($el)\]='$val'"				
			}
			append cond_cmd " AND \[$table\_$FieldsMap($el)\]='$val'"
			set par_found 1
		}
	}
	if {$par_found==0} {error "The condition parameter '$par' doesn't exist in FieldsMap array"}
}
if {$newTestCreated && $update_cmd(TS)!=""} {
	if {[dbcommand "UPDATE TEST SET [string trim $update_cmd(TS) ,] WHERE TEST_ID='$TestID'"]!=1} {
		error "Failed to update 'TEST' table"
	}	
}
if {$newTestSetInstance && $update_cmd(TC)!=""} {
	if {[dbcommand "UPDATE TESTCYCL SET [string trim $update_cmd(TC) ,] WHERE TC_TESTCYCL_ID='$tcInst'"]!=1} {
		error "Failed to update 'TESTCYCL' table"
	}
}

set tcInst [dbcommand "SELECT TC_TESTCYCL_ID FROM TESTCYCL JOIN TEST ON (TC_TEST_ID=TS_TEST_ID) WHERE TC_CYCLE_ID=$TestSetID AND TS_NAME='$test' $cond_cmd"]
if {[llength $tcInst]>1} {
	error "Found more than one ([llength $tcInst]) instances of '$test' in '$TestSetName' TestSet"
}
DEBUG " Found '$tcInst' ([llength $tcInst] instances) of '$test' in TestLab"
# Get current status
if {[set cur_status [lindex [dbcommand "SELECT TC_STATUS FROM TESTCYCL WHERE TC_TESTCYCL_ID='$tcInst'"] 0]]==""} {
	error "error cannot  get current status for TC_TESTCYCL_ID='$tcInst' (test '$test')"
}
DEBUG " Current status '$cur_status'"

if {0 &&[lsearch [list "No Run" "N/A"] $result]!=-1} {
	# DISABLED!!!!
	#
	DEBUG "result is '$result' so RUN line will not be created"
	if {[dbcommand "UPDATE TESTCYCL SET TC_STATUS='$result' WHERE TC_TESTCYCL_ID='$tcInst'"]==""} {
		error "error cannot change status for TC_TESTCYCL_ID='$tcInst' (test '$test')"
	}
} else {
	if {$cur_status==$result} {
		if {$result=="Blocked"} {
			puts "Warning! - the requested status is 'Blocked' - no lines will be added to RUN tables"
		} else {
			DEBUG " The current status ($cur_status) and requested status is the same - set temporary status 'Blocked'"
			if {[dbcommand "UPDATE TESTCYCL SET TC_STATUS='Blocked' WHERE TC_TESTCYCL_ID='$tcInst'"]==""} {
				error "error cannot change status for TC_TESTCYCL_ID='$tcInst' (test '$test')"
			}
		}
	}
	rest_update	$tcInst
	rest_close
}

puts "OK! update ALM completed successfully (test '$test' in '$path', new result '$result', previous status was '$cur_status')"
exit 0