/*
 * Business Process titles "<type><U+2028><name>" (continuos-platform-monitoring-app,
 * 99_locals.tf): the file of the Business Process has one line per node, so the
 * line break is U+2028, shown by the browser as a space. Here it becomes a <br>,
 * inside a span: the tile title is a flex container, a bare <br> would be ignored.
 * The first part (the type) gets its own span, styled by the theme (default.less).
 * Run on every rendered container (first load, navigation, auto-refresh)
 */
(function ($) {
    'use strict';

    var LS = '\u2028';

    function breakTitles(root) {
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                return node.nodeValue.indexOf(LS) === -1 ? NodeFilter.FILTER_SKIP : NodeFilter.FILTER_ACCEPT;
            }
        });

        var nodes = [];
        while (walker.nextNode()) {
            nodes.push(walker.currentNode);
        }

        nodes.forEach(function (node) {
            // no markup inside form controls and scripts: a space there
            if ($(node.parentNode).is('option, textarea, script, style')) {
                node.nodeValue = node.nodeValue.split(LS).join(' ');
                return;
            }

            var span = document.createElement('span');
            span.className = 'pagopa-title';
            node.nodeValue.split(LS).forEach(function (part, i) {
                if (i === 0) {
                    var type = document.createElement('span');
                    type.className = 'pagopa-title-type';
                    type.textContent = part;
                    span.appendChild(type);
                    return;
                }
                span.appendChild(document.createElement('br'));
                span.appendChild(document.createTextNode(part));
            });
            node.parentNode.replaceChild(span, node);
        });
    }

    // grid of the first level (domains): every tile links to a node
    // (...&node=<domain>) and has no two-line title (hosts and AKS namespaces have
    // it, from the second level on); the leaves (checks) link to Icinga DB
    function markTopTiles(root) {
        $(root).find('.tiles').addBack('.tiles').each(function () {
            var tiles = $(this).children('div');
            var top = tiles.length > 0 && tiles.toArray().every(function (tile) {
                var link = $(tile).children('a').first();
                return link.length > 0
                    && /[?&]node=/.test(link.attr('href') || '')
                    && link.find('.pagopa-title').length === 0;
            });
            $(this).toggleClass('pagopa-top-tiles', top);
        });
    }

    function render(root) {
        breakTitles(root);
        markTopTiles(root);
    }

    $(document).on('rendered', function (e) {
        render(e.target);
    });

    $(function () {
        render(document.body);
    });
}(jQuery));
