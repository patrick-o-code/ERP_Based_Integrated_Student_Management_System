<?php
require_once 'Warehouse.php';

echo "=== ACCESS LOG - FAILED LOGIN ATTEMPTS (Last 20) ===\n";
$access_log_RET = DBGet( "SELECT SYEAR, USERNAME, IP_ADDRESS, STATUS, CREATED_AT, USER_AGENT
	FROM access_log
	ORDER BY CREATED_AT DESC
	LIMIT 20" );

if ( $access_log_RET ) {
	foreach ( $access_log_RET as $row ) {
		echo "Username: " . $row['USERNAME'] . " | Status: " . $row['STATUS'] . " | IP: " . $row['IP_ADDRESS'] . " | Created: " . $row['CREATED_AT'] . "\n";
	}
} else {
	echo "No access log entries found\n";
}

echo "\n=== RECENT FAILED LOGINS (Last 10 mins, Status B=Banned or NULL) ===\n";
$DatabaseType = 'mysql'; // From config
$failed_login_RET = DBGet( "SELECT
	COUNT(CASE WHEN STATUS IS NULL OR STATUS='B' THEN 1 END) AS FAILED_COUNT,
	COUNT(CASE WHEN STATUS='B' THEN 1 END) AS BANNED_COUNT,
	IP_ADDRESS
	FROM access_log
	WHERE CREATED_AT > (CURRENT_TIMESTAMP - INTERVAL 10 minute)
	GROUP BY IP_ADDRESS
	ORDER BY CREATED_AT DESC" );

if ( $failed_login_RET ) {
	foreach ( $failed_login_RET as $row ) {
		echo "IP: " . $row['IP_ADDRESS'] . " | Failed: " . $row['FAILED_COUNT'] . " | Banned: " . $row['BANNED_COUNT'] . "\n";
	}
} else {
	echo "No recent failed logins\n";
}

echo "\n=== STAFF FAILED_LOGIN COUNTER ===\n";
$staff_RET = DBGet( "SELECT USERNAME, FAILED_LOGIN FROM staff WHERE SYEAR='" . Config( 'SYEAR' ) . "'" );
if ( $staff_RET ) {
	foreach ( $staff_RET as $row ) {
		echo $row['USERNAME'] . ": " . ( $row['FAILED_LOGIN'] ?: 'NULL' ) . "\n";
	}
}
?>
