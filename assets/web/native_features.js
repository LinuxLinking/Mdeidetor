(function () {
  'use strict';

  var lastSelection = null;
  var lastDomRange = null;
  var diagramCounter = 0;
  var mermaidScrollTimer = null;

  function post(type, payload) {
    try {
      if (window.MdBridge) {
        window.MdBridge.postMessage(JSON.stringify({ type: type, payload: payload || {} }));
      }
    } catch (_) {}
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, function (ch) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch];
    });
  }

  function copyCode(code) {
    post('codeCopy', { text: code });
  }

  function enhanceCodeBlocks(root) {
    (root || document).querySelectorAll('pre code').forEach(function (code) {
      if (code.dataset.nativeEnhanced === 'true') return;
      code.dataset.nativeEnhanced = 'true';
      var pre = code.closest('pre');
      if (!pre) return;
      var language = Array.from(code.classList).find(function (name) {
        return name.indexOf('language-') === 0;
      });
      var toolbar = document.createElement('div');
      var existingToolbar = pre.querySelector('.native-code-toolbar');
      if (existingToolbar) {
        toolbar = existingToolbar;
      } else {
        toolbar.className = 'native-code-toolbar';
        toolbar.innerHTML = '<span>' + escapeHtml(language ? language.slice(9) : 'text') +
          '</span><button type="button" aria-label="Copy code">Copy</button>';
        pre.insertBefore(toolbar, code);
      }
      var copyButton = toolbar.querySelector('button');
      if (copyButton) copyButton.addEventListener('click', function () {
        copyCode(code.textContent || '');
      });
      pre.classList.add('native-code-block');
      if (window.hljs) {
        try { window.hljs.highlightElement(code); } catch (_) {}
      }
    });
  }

  function visible(element) {
    var rect = element.getBoundingClientRect();
    return rect.bottom > 0 && rect.top < (window.innerHeight || document.documentElement.clientHeight) &&
      rect.right > 0 && rect.left < (window.innerWidth || document.documentElement.clientWidth);
  }

  function renderMermaid(root) {
    var scope = root || document;
    // Native rendering creates hosts directly. Keep this fallback for HTML
    // inserted by other callers, but never render while the user is scrolling.
    scope.querySelectorAll('pre code.language-mermaid').forEach(function (code) {
      var pre = code.closest('pre');
      if (!pre || pre.dataset.nativeMermaid === 'true') return;
      var host = document.createElement('div');
      host.className = 'native-mermaid';
      host.setAttribute('role', 'img');
      host.setAttribute('data-mermaid', (code.textContent || '').trim());
      pre.replaceWith(host);
    });
    scheduleVisibleMermaid();
  }

  function scheduleVisibleMermaid() {
    if (mermaidScrollTimer) clearTimeout(mermaidScrollTimer);
    mermaidScrollTimer = setTimeout(function () {
      mermaidScrollTimer = null;
      document.querySelectorAll('.native-mermaid[data-mermaid]').forEach(function (host) {
        if (visible(host) && host.dataset.mermaidRequested !== 'true' &&
            !host.querySelector('svg') && window.bridge && window.bridge.renderMermaid) {
          var source = host.getAttribute('data-mermaid') || '';
          host.dataset.mermaidRequested = 'true';
          // Native accepts the source as a compatibility fallback and derives
          // the canonical MD5 key before looking in its memory cache.
          window.bridge.renderMermaid(source, source);
        }
      });
    }, 150);
  }

  function refresh(root) {
    var scope = root || document;
    enhanceCodeBlocks(scope);
    renderMermaid(scope);
  }

  function absoluteOffset(root, target, localOffset) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    var total = 0;
    var node;
    while ((node = walker.nextNode())) {
      if (node === target) return total + Math.min(localOffset, node.nodeValue.length);
      total += node.nodeValue.length;
    }
    return total;
  }

  window.nativeFeatures = {
    refresh: refresh,
    setTheme: function (variables) {
      document.documentElement.classList.add('theme-transitioning');
      Object.keys(variables || {}).forEach(function (key) {
        document.documentElement.style.setProperty(key, variables[key]);
      });
      window.setTimeout(function () {
        document.documentElement.classList.remove('theme-transitioning');
      }, 500);
    },
    insertAtSelection: function (value) {
      if (document.queryCommandSupported && document.queryCommandSupported('insertText')) {
        document.execCommand('insertText', false, value);
        post('changed', { md: window.bridge && window.bridge.getContent ? window.bridge.getContent() : '' });
        return;
      }
      var selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) return;
      var range = selection.getRangeAt(0);
      range.deleteContents();
      range.insertNode(document.createTextNode(value));
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
      post('changed', { md: window.bridge && window.bridge.getContent ? window.bridge.getContent() : '' });
    },
    formatSelection: function (command, value) {
      if (!document.queryCommandSupported || !document.queryCommandSupported(command)) return;
      if (lastDomRange) {
        var selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(lastDomRange);
      }
      document.execCommand(command, false, value || null);
      post('changed', { md: window.bridge && window.bridge.getContent ? window.bridge.getContent() : '' });
    },
    rememberSelection: function (range) {
      lastDomRange = range ? range.cloneRange() : null;
    },
    applyPatches: function (patches) {
      // The TypeScript bridge owns the patch protocol. Keep this shim for
      // callers that use the legacy nativeFeatures surface.
      if (window.bridge && typeof window.bridge.applyPatches === 'function') {
        window.bridge.applyPatches(patches || []);
        return;
      }
      var preview = document.getElementById('native-render-preview');
      if (!preview) {
        preview = document.createElement('div');
        preview.id = 'native-render-preview';
        preview.hidden = true;
        document.body.appendChild(preview);
      }
      (patches || []).forEach(function (patch) {
        var nodes = [];
        (patch.html || []).forEach(function (html) {
          var template = document.createElement('template');
          template.innerHTML = html;
          nodes.push.apply(nodes, Array.from(template.content.childNodes));
        });
        for (var i = 0; i < patch.deleteCount; i++) {
          var old = preview.children[patch.from];
          if (old) old.remove();
        }
        var reference = preview.children[patch.from] || null;
        nodes.forEach(function (node) { preview.insertBefore(node, reference); });
      });
      refresh();
    },
    applyNativeMermaid: function (source, svg) {
      document.querySelectorAll('.native-mermaid[data-mermaid]').forEach(function (host) {
        if (host.getAttribute('data-mermaid') === source) {
          host.innerHTML = svg;
          host.dataset.mermaidRequested = 'true';
        }
      });
    },
    applyNativeLatex: function (source, html, display) {
      var selector = display ? '.latex-block[data-latex]' : '.latex-inline[data-latex]';
      document.querySelectorAll(selector).forEach(function (host) {
        if (host.getAttribute('data-latex') === source) host.innerHTML = html;
      });
    }
  };

  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', function () {
      if (!lastDomRange) return;
      var element = lastDomRange.startContainer.parentElement;
      if (element) element.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    });
  }

  document.addEventListener('scroll', scheduleVisibleMermaid, { passive: true, capture: true });

  window.setTimeout(function () {
    if (window.mermaid) window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
    refresh();
  }, 0);
})();
