/**
 * MarkDownInputPreview() function JS
 *
 * @since 12.5
 *
 * @package RosarioSIS
 */

csp.functions.markDownInputPreview = {
	preview: function() {
		MarkDownInputPreview(this.dataset.id);
	},
	onEvents: function() {
		$('.md-preview .tab').on('click', csp.functions.markDownInputPreview.preview);
	}
}

$(csp.functions.markDownInputPreview.onEvents);
