<?php
require_once 'Warehouse.php';

echo "=== UPDATING PROJECT NAME ===\n\n";

// Get current config
$old_name = Config( 'NAME' );
echo "Current NAME: " . $old_name . "\n";

// Update to new name
$new_name = 'Cloud Avengers Student Information System';
Config( 'NAME', $new_name );

echo "New NAME: " . $new_name . "\n";

echo "\n✓ Project name updated successfully!\n";
echo "\nThe following locations use this name:\n";
echo "  - Login page title\n";
echo "  - Configuration settings\n";
echo "  - Student ID field label\n";
echo "  - Help text\n";
echo "  - Database backup filenames\n";
?>
