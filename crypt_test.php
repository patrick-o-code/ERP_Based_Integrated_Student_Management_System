<?php
// Quick test to check SHA512 crypt() support on this PHP build
echo "CRYPT_SHA512 defined: ";
echo defined('CRYPT_SHA512') ? CRYPT_SHA512 . PHP_EOL : "not defined\n";
$plain = 'testpassword';
$salt = '$6$' . substr(sha1(mt_rand()), 0, 16);
echo "Salt: $salt\n";
$hashed = crypt($plain, $salt);
echo "crypt output: $hashed\n";
// Verify crypt can validate same password (simulate match_password)
$verify = ( crypt($plain, $hashed) === $hashed ) ? 'yes' : 'no';
echo "crypt verifies same password: $verify\n";
?>