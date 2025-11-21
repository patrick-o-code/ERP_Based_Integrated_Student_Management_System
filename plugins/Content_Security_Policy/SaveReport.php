<?php
/**
 * Save CSP violation report
 *
 * @package Content Security Policy plugin
 */

chdir( '../..' );

require_once 'Warehouse.php';

if ( empty( $_SERVER['CONTENT_TYPE'] )
	|| $_SERVER['CONTENT_TYPE'] !== 'application/csp-report' )
{
	return _errorDie( 'Not a CSP report' );
}

$json = json_decode( file_get_contents('php://input'), true );

if ( empty( $json['csp-report'] ) )
{
	return _errorDie( 'No CSP report found' );
}

$insert_columns = [
	'FULL_REPORT' => DBEscapeString( json_encode( $json['csp-report'] ) ),
	'VIOLATED_DIRECTIVE' => DBEscapeString( str_replace( '-elem', '', $json['csp-report']['violated-directive'] ) ),
	'BLOCKED_URI' => DBEscapeString( $json['csp-report']['blocked-uri'] ),
	'SCRIPT_SAMPLE' => DBEscapeString( trim( issetVal( $json['csp-report']['script-sample'], '' ) ) ),
];

// Only save unique CSP report once a day.
$csp_reported_today = DBGetOne( "SELECT 1
	FROM csp_reports
	WHERE CREATED_AT>='" . DBDate() . " 00:00:00'
	AND FULL_REPORT='" . DBEscapeString( $insert_columns['FULL_REPORT'] ) . "'");

if ( ! $csp_reported_today )
{
	DBInsert( 'csp_reports', $insert_columns );
}

// Destroy session.
session_unset();

session_destroy();

/**
 * JSON Error and Die.
 * Destroy session.
 *
 * Local function
 *
 * @param string $error Error message.
 */
function _errorDie( $error )
{
	// Destroy session.
	session_unset();

	session_destroy();

	http_response_code( 500 );

	header( 'Content-type: application/json; charset=utf-8' );

	echo json_encode( [ 'error' => $error ] );

	error_log( 'Content Security Policy plugin error: ' . $error );

	exit;
}
