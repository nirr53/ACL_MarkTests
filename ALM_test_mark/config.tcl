
set DEBUG 0

set logfilename {\\netapp1\Sip-qa\ALM_aut_update\ForIPP\ALM_IPP_update.log}
set logfilesizemax 500000000
set mail_server_ip 10.1.1.60
set sender_name almupdate
#set s2_service_men alex.rodikov
set SQL_Server aclsql01\\aclalm 
set SQL_Database default_ip_phone_db
#set SQL_Database default_tp_72_db_restored
set SQL_User td
set SQL_Pass tdtdtd
set REST_URL  http://aclalmqa:8080/qcbin
set REST_URL_project $REST_URL/rest/domains/DEFAULT/projects/IP_Phone

set ALM_user qa-cmbu
set ALM_password Qacmbu202
