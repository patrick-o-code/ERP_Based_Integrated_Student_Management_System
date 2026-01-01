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

$csp_report = $json['csp-report'];

// Do not save violations triggered by browser extensions.
$source_file_skip = [
	'moz-extension',
	'chrome-extension',
	'safari-extension',
];

if ( in_array( $csp_report['source-file'], $source_file_skip ) )
{
	return _errorDie( 'Skip CSP violation triggered by browser extension' );
}

// Do not save violations triggered by the following domains.
$domain_skip = [
	'https://www.google-analytics.com', // AJAX request to Google Analytics
	'https://www.gstatic.com', // CSS file injected by Google Translate
	'https://me.kis.v2.scr.kaspersky-labs.com', // JS script injected by Kaspersky antivirus
];

foreach ( $domain_skip as $domain )
{
	if ( stripos( $csp_report['blocked-uri'], $domain ) === 0 )
	{
		return _errorDie( 'Skip CSP violation triggerd by domain: ' . $domain );
	}
}

// Do not save the following violations
/**
 * Really common violation but was not able to trace it...
 *
 * "violated-directive": "script-src-elem",
 * "blocked-uri": "inline",
 * "script-sample": "function yf9behvg8uwqfnuk() { if (!0 ==="
 */
if ( $csp_report['violated-directive'] === 'script-src-elem'
	&& $csp_report['blocked-uri'] === 'inline'
	&& $csp_report['script-sample'] === 'function yf9behvg8uwqfnuk() { if (!0 ===' )
{
	return _errorDie( 'Skip CSP violation triggered by script sample: "' . $csp_report['script-sample'] . '"' );
}

/**
 * Violation triggered just before AJAX request to Google Analytics (see above)
 *
 * "violated-directive": "script-src-elem",
 * "blocked-uri": "blob",
 * "line-number": 1,
 * "column-number": 267
 */
if ( $csp_report['violated-directive'] === 'script-src-elem'
	&& $csp_report['blocked-uri'] === 'blob'
	&& $csp_report['line-number'] === 1
	&& $csp_report['column-number'] === 267 )
{
	return _errorDie( 'Skip CSP violation triggered by blob script: line 1, column 267' );
}

$insert_columns = [
	'FULL_REPORT' => DBEscapeString( json_encode( $csp_report ) ),
	'VIOLATED_DIRECTIVE' => DBEscapeString( str_replace( '-elem', '', $csp_report['violated-directive'] ) ),
	'BLOCKED_URI' => DBEscapeString( $csp_report['blocked-uri'] ),
	'SCRIPT_SAMPLE' => DBEscapeString( trim( issetVal( $csp_report['script-sample'], '' ) ) ),
];

// Only save unique CSP report once a day.
$csp_reported_today = DBGetOne( "SELECT 1
	FROM csp_reports
	WHERE CREATED_AT>='" . DBDate() . " 00:00:00'
	AND FULL_REPORT='" . DBEscapeString( json_encode( $csp_report ) ) . "'" );

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
