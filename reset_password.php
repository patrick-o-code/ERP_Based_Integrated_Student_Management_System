<?php
require_once 'Warehouse.php';

// Check if username and password provided via command line or form
$username = isset( $_GET['username'] ) ? trim( $_GET['username'] ) : ( isset( $argv[1] ) ? $argv[1] : '' );
$new_password = isset( $_GET['password'] ) ? trim( $_GET['password'] ) : ( isset( $argv[2] ) ? $argv[2] : '' );

// Display form if accessed via web
if ( php_sapi_name() !== 'cli' && empty( $username ) ) {
	?>
	<!DOCTYPE html>
	<html>
	<head>
		<title>Reset Password</title>
		<style>
			body { font-family: Arial, sans-serif; margin: 40px; }
			.container { max-width: 400px; margin: 0 auto; }
			label { display: block; margin-top: 10px; font-weight: bold; }
			input { width: 100%; padding: 8px; margin-top: 5px; box-sizing: border-box; }
			button { margin-top: 15px; padding: 10px 20px; background-color: #007bff; color: white; border: none; cursor: pointer; }
			button:hover { background-color: #0056b3; }
			.result { margin-top: 20px; padding: 10px; border-radius: 5px; }
			.success { background-color: #d4edda; color: #155724; }
			.error { background-color: #f8d7da; color: #721c24; }
		</style>
	</head>
	<body>
		<div class="container">
			<h1>Reset User Password</h1>
			<form method="GET">
				<label for="username">Username (staff or student):</label>
				<input type="text" id="username" name="username" required placeholder="e.g., admin, teacher, student" />
				
				<label for="password">New Password:</label>
				<input type="password" id="password" name="password" required placeholder="Enter new password" />
				
				<button type="submit">Reset Password</button>
			</form>
		</div>
	</body>
	</html>
	<?php
	exit;
}

// Validate input
if ( empty( $username ) || empty( $new_password ) ) {
	die( "Error: Username and password required.\n" );
}

if ( strlen( $new_password ) < 3 ) {
	die( "Error: Password must be at least 3 characters.\n" );
}

// Hash the password
require_once 'functions/Password.php';
$hashed_password = encrypt_password( $new_password );

// Try to update staff first
$staff_updated = false;
$staff_RET = DBGet( "SELECT STAFF_ID FROM staff WHERE UPPER(USERNAME)=UPPER('" . DBEscapeString( $username ) . "')" );

if ( $staff_updated = ! empty( $staff_RET ) ) {
	DBQuery( "UPDATE staff 
		SET PASSWORD='" . DBEscapeString( $hashed_password ) . "',
		FAILED_LOGIN=NULL
		WHERE UPPER(USERNAME)=UPPER('" . DBEscapeString( $username ) . "')" );
	echo "✓ Password reset successfully for staff user: " . $staff_RET[1]['STAFF_ID'] . "\n";
}

// If not staff, try students
if ( ! $staff_updated ) {
	$student_RET = DBGet( "SELECT STUDENT_ID FROM students WHERE UPPER(USERNAME)=UPPER('" . DBEscapeString( $username ) . "')" );
	
	if ( ! empty( $student_RET ) ) {
		DBQuery( "UPDATE students 
			SET PASSWORD='" . DBEscapeString( $hashed_password ) . "',
			FAILED_LOGIN=NULL
			WHERE UPPER(USERNAME)=UPPER('" . DBEscapeString( $username ) . "')" );
		echo "✓ Password reset successfully for student user: " . $student_RET[1]['STUDENT_ID'] . "\n";
	} else {
		die( "Error: User '$username' not found in staff or students table.\n" );
	}
}

echo "New password: " . $new_password . "\n";
echo "\nYou can now login with:\n";
echo "  Username: " . $username . "\n";
echo "  Password: " . $new_password . "\n";
?>
