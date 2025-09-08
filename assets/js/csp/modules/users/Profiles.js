/**
 * User Profiles program (Users module) JS
 *
 * @since 12.5
 *
 * @package RosarioSIS
 */

csp.modules.users.profiles = {
	addNew: function() {
		addHTML($('#new_profile_html').val(), 'new_profile_div', true);
	},
	onEvents: function() {
		$('.onclick-add-new-profile').on('click', csp.modules.users.profiles.addNew);
	}
}

$(csp.modules.users.profiles.onEvents);
