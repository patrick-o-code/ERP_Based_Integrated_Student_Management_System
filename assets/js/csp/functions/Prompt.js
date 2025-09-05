/**
 * DeletePrompt() & Prompt() functions JS
 *
 * @since 12.5
 *
 * @package RosarioSIS
 */

/**
 * Cancel (Delete) Prompt
 * If inside colorBox, close it. Otherwise, go back in browser history.
 */
csp.functions.promptCancel = function() {
	if ($(this).closest('#colorbox').length) {
		$.colorbox.close();
	} else {
		self.history.go(-1);
	}
}

$('.button-prompt-cancel').on('click', csp.functions.promptCancel);
