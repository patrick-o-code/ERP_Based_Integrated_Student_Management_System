<?php
// Simulate the login check from index.php
require_once 'Warehouse.php';

$username = 'admin';
$password = 'admin';
$syear = Config( 'SYEAR' );

echo "=== SIMULATING LOGIN FOR: $username ===\n";
echo "SYEAR: $syear\n\n";

// Step 1: Check staff
echo "Step 1: Lookup staff user...\n";
$login_RET = DBGet( "SELECT USERNAME,PROFILE,STAFF_ID,LAST_LOGIN,FAILED_LOGIN,PASSWORD
	FROM staff
	WHERE SYEAR='" . $syear . "'
	AND UPPER(USERNAME)=UPPER('" . $username . "')" );

if ( $login_RET ) {
	echo "  Found staff user: " . $login_RET[1]['USERNAME'] . " (Profile: " . $login_RET[1]['PROFILE'] . ")\n";
	
	// Step 2: Check password
	echo "Step 2: Checking password...\n";
	$password_match = match_password( $login_RET[1]['PASSWORD'], $password );
	echo "  Password match: " . ( $password_match ? 'YES' : 'NO' ) . "\n";
	
	if ( ! $password_match ) {
		echo "  ERROR: Password mismatch!\n";
		$login_RET = false;
	}
} else {
	echo "  Staff user not found!\n";
}

if ( $login_RET ) {
	echo "\nStep 3: Check profile...\n";
	if ( in_array( $login_RET[1]['PROFILE'], [ 'admin', 'teacher', 'parent' ] ) ) {
		echo "  Profile is valid: " . $login_RET[1]['PROFILE'] . "\n";
		echo "  Login SUCCESSFUL - session would be created\n";
		echo "  STAFF_ID: " . $login_RET[1]['STAFF_ID'] . "\n";
		echo "  LAST_LOGIN: " . ( $login_RET[1]['LAST_LOGIN'] ?: 'NULL' ) . "\n";
	} else {
		echo "  Profile is invalid: " . $login_RET[1]['PROFILE'] . "\n";
		echo "  ERROR: Invalid profile\n";
	}
} else {
	echo "\nLogin FAILED - attempting student lookup...\n";
}
?>
