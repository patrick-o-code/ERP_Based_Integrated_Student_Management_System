/**
 * BottomButtonBackUpdate() ProgramFunctions JS
 *
 * @since 12.5
 *
 * @package RosarioSIS
 */

/**
 * "Back to List" Bottom.php button update
 * Use `data-text`, `data-href` & `data-after` attributes
 *
 * @return {boolean} True if updated.
 */
csp.programFunctions.bottomButtonBackUpdate = function() {
	var b = document.getElementById('bottom_button_back_update');

	if (! b) {
		return false;
	}

	$('#BottomButtonBack span').text(b.dataset.text);

	$('#BottomButtonBack').removeClass('hide')
		.attr('href', b.dataset.href)
		.attr('title', b.dataset.text);

	/**
	 * Fix CSP inline script violation: do NOT use jQuery .after() function here
	 * while retaining the possibility to load <script> inside the injected HTML
	 *
	 * @link https://developer.mozilla.org/en-US/docs/Web/API/Element/insertAdjacentHTML
	 */
	document.getElementById('BottomButtonBack').insertAdjacentHTML('afterend', b.dataset.after);

	return true;
}

$(csp.programFunctions.bottomButtonBackUpdate);
