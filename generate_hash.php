<?php
// Generate password hash for RosarioSIS using SHA512 crypt
// Replicate the encrypt_password function

$password = 'admin';
$rand = rand( 999999999, 9999999999 );
$salt = '$6$' . substr( sha1( $rand ), 0, 16 );
$hash = crypt( $password, $salt );

echo "Password: $password\n";
echo "Hash: $hash\n";
echo "\nSQL Command:\n";
echo "UPDATE staff SET password = '$hash' WHERE username = 'admin';\n";
?>
