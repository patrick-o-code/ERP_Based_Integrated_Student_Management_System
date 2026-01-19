<?php
require_once 'Warehouse.php';

echo "=== RESETTING FAILED LOGIN COUNTERS ===\n";

// Reset FAILED_LOGIN for all staff
DBQuery( "UPDATE staff SET FAILED_LOGIN=NULL WHERE SYEAR='" . Config( 'SYEAR' ) . "'" );
echo "Updated staff FAILED_LOGIN counters\n";

// Reset FAILED_LOGIN for all students
DBQuery( "UPDATE students SET FAILED_LOGIN=NULL" );
echo "Updated students FAILED_LOGIN counters\n";

echo "\n=== CLEARED ACCESS LOG (last 1 hour) ===\n";
DBQuery( "DELETE FROM access_log WHERE CREATED_AT > (CURRENT_TIMESTAMP - INTERVAL 1 hour)" );
echo "Deleted old access log entries\n";

echo "\n=== CURRENT STAFF STATE ===\n";
$staff_RET = DBGet( "SELECT USERNAME, FAILED_LOGIN FROM staff WHERE SYEAR='" . Config( 'SYEAR' ) . "'" );
foreach ( $staff_RET as $row ) {
	echo $row['USERNAME'] . ": FAILED_LOGIN=" . ( $row['FAILED_LOGIN'] ?: 'NULL' ) . "\n";
}

echo "\n✓ You can now try logging in again with:\n";
echo "  Username: admin\n";
echo "  Password: admin\n";
echo "\n  (or teacher/teacher, parent/parent, student/student)\n";
?>
