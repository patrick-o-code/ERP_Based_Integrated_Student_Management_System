/**
 * Search() function JS
 *
 * @since 12.5
 *
 * @package RosarioSIS
 */

/**
 * Show Student Grade Level when selected Profile is "Parent"
 * Find a User form
 */
csp.functions.searchProfile = function() {
	$('#student_grade_level_row').toggle(this.value === 'parent');
}

$('#search #profile').on('change', csp.functions.searchProfile);
