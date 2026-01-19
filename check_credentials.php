<?php
require_once 'Warehouse.php';

echo "=== STAFF USERS ===\n";
$staff_RET = DBGet( "SELECT USERNAME, PASSWORD, PROFILE, FAILED_LOGIN, LAST_LOGIN 
	FROM staff 
	WHERE SYEAR='" . Config( 'SYEAR' ) . "'
	LIMIT 10" );

if ( $staff_RET ) {
	foreach ( $staff_RET as $row ) {
		echo "Username: " . $row['USERNAME'] . "\n";
		echo "Profile: " . $row['PROFILE'] . "\n";
		echo "Password hash length: " . strlen( $row['PASSWORD'] ) . "\n";
		echo "Password hash: " . substr($row['PASSWORD'], 0, 50) . "...\n";
		echo "Failed Login: " . $row['FAILED_LOGIN'] . "\n";
		echo "Last Login: " . $row['LAST_LOGIN'] . "\n";
		echo "---\n";
	}
} else {
	echo "No staff users found for SYEAR " . Config( 'SYEAR' ) . "\n";
}

echo "\n=== STUDENT USERS ===\n";
$students_RET = DBGet( "SELECT USERNAME, PASSWORD, FAILED_LOGIN, LAST_LOGIN 
	FROM students 
	LIMIT 10" );

if ( $students_RET ) {
	foreach ( $students_RET as $row ) {
		echo "Username: " . $row['USERNAME'] . "\n";
		echo "Password hash length: " . strlen( $row['PASSWORD'] ) . "\n";
		echo "Password hash: " . substr($row['PASSWORD'], 0, 50) . "...\n";
		echo "Failed Login: " . $row['FAILED_LOGIN'] . "\n";
		echo "Last Login: " . $row['LAST_LOGIN'] . "\n";
		echo "---\n";
	}
} else {
	echo "No students found\n";
}

echo "\n=== CONFIG SYEAR ===\n";
echo "DefaultSyear: " . Config( 'SYEAR' ) . "\n";
?>
