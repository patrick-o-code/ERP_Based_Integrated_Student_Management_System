<?php
require_once 'Warehouse.php';
require_once 'functions/Password.php';

echo "=== PASSWORD VERIFICATION TEST ===\n";
echo "DefaultSyear: " . Config( 'SYEAR' ) . "\n";
echo "FAILED_LOGIN_LIMIT: " . Config( 'FAILED_LOGIN_LIMIT' ) . "\n";
echo "\n";

// Test with known users
$test_users = [
	['username' => 'admin', 'password' => 'admin'],
	['username' => 'teacher', 'password' => 'teacher'],
	['username' => 'parent', 'password' => 'parent'],
	['username' => 'student', 'password' => 'student'],
];

foreach ( $test_users as $test_user ) {
	echo "Testing: " . $test_user['username'] . " with password: " . $test_user['password'] . "\n";
	
	// Check staff table
	$staff_RET = DBGet( "SELECT PASSWORD FROM staff 
		WHERE SYEAR='" . Config( 'SYEAR' ) . "'
		AND UPPER(USERNAME)=UPPER('" . $test_user['username'] . "')" );
	
	if ( $staff_RET ) {
		$stored_hash = $staff_RET[1]['PASSWORD'];
		echo "  Found in staff table\n";
		echo "  Stored hash: " . substr($stored_hash, 0, 50) . "...\n";
		
		$matches = match_password( $stored_hash, $test_user['password'] );
		echo "  match_password() result: " . ( $matches ? 'YES - MATCH' : 'NO - MISMATCH' ) . "\n";
		
		// Debug: test crypt directly
		$crypt_result = crypt( $test_user['password'], $stored_hash );
		echo "  Direct crypt result: " . substr($crypt_result, 0, 50) . "...\n";
		echo "  Hashes equal: " . ( $crypt_result === $stored_hash ? 'yes' : 'no' ) . "\n";
	} else {
		// Check students table
		$student_RET = DBGet( "SELECT PASSWORD FROM students 
			WHERE UPPER(USERNAME)=UPPER('" . $test_user['username'] . "')" );
		
		if ( $student_RET ) {
			$stored_hash = $student_RET[1]['PASSWORD'];
			echo "  Found in students table\n";
			echo "  Stored hash: " . substr($stored_hash, 0, 50) . "...\n";
			
			$matches = match_password( $stored_hash, $test_user['password'] );
			echo "  match_password() result: " . ( $matches ? 'YES - MATCH' : 'NO - MISMATCH' ) . "\n";
			
			// Debug: test crypt directly
			$crypt_result = crypt( $test_user['password'], $stored_hash );
			echo "  Direct crypt result: " . substr($crypt_result, 0, 50) . "...\n";
			echo "  Hashes equal: " . ( $crypt_result === $stored_hash ? 'yes' : 'no' ) . "\n";
		} else {
			echo "  User not found in either table\n";
		}
	}
	echo "\n";
}

echo "=== DATABASE CONNECTION TEST ===\n";
$test_query = DBGet( "SELECT 1 as test" );
echo "Database query result: ";
print_r( $test_query );
?>
