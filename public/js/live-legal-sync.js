/**
 * Oneova Live Legal & Governance Cloud Sync (`platform_cms_docs`)
 * Ultra-lightweight (<4 KB, zero external dependencies) real-time reader for
 * standalone statutory HTML pages (`/terms.html`, `/privacy.html`, etc.).
 *
 * Whenever an Admin publishes an update in the Oneova Mobile App or Web CMS,
 * this script fetches the live Firestore document and renders the latest
 * version badge, effective date, plain-language "In Short" summary, and
 * structured cloud sections/amendments while keeping the full static HTML
 * instrument intact for search crawlers, offline reading, and A4 PDF printing.
 */
(function () {
  var PROJECT_ID = 'mpepe-2b4bd';
  var scriptEl =
    document.currentScript || document.querySelector('script[data-cms-doc]');
  var docId = scriptEl && scriptEl.getAttribute('data-cms-doc');
  if (!docId) return;

  // Synchronize theme preference with main Oneova React web portal if present
  try {
    var mainTheme = localStorage.getItem('oneova_theme');
    var legalTheme = localStorage.getItem('oneova_legal_theme');
    if (!legalTheme && (mainTheme === 'dark' || mainTheme === 'light')) {
      document.documentElement.setAttribute('data-theme', mainTheme);
    }
  } catch (_) {}

  function decodeValue(v) {
    if (!v || typeof v !== 'object') return null;
    if ('stringValue' in v) return v.stringValue;
    if ('booleanValue' in v) return Boolean(v.booleanValue);
    if ('integerValue' in v) return Number(v.integerValue);
    if ('doubleValue' in v) return Number(v.doubleValue);
    if ('timestampValue' in v) return v.timestampValue;
    if ('arrayValue' in v) {
      var vals = (v.arrayValue && v.arrayValue.values) || [];
      return vals.map(decodeValue);
    }
    if ('mapValue' in v) {
      var fields = (v.mapValue && v.mapValue.fields) || {};
      var out = {};
      Object.keys(fields).forEach(function (k) {
        out[k] = decodeValue(fields[k]);
      });
      return out;
    }
    return null;
  }

  function decodeDoc(raw) {
    var fields = (raw && raw.fields) || {};
    var out = {};
    Object.keys(fields).forEach(function (k) {
      out[k] = decodeValue(fields[k]);
    });
    return out;
  }

  function el(tag, attrs, text) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        if (k === 'style') {
          node.style.cssText = attrs[k];
        } else if (k === 'className') {
          node.className = attrs[k];
        } else {
          node.setAttribute(k, attrs[k]);
        }
      });
    }
    if (typeof text === 'string') {
      node.textContent = text;
    }
    return node;
  }

  function renderLiveBanner(doc) {
    var shell = document.querySelector('main.doc-shell');
    if (!shell || document.getElementById('oneova-live-cms-banner')) return;

    var box = el('section', {
      id: 'oneova-live-cms-banner',
      style:
        'margin: 0 0 22px 0; padding: 15px 18px; border-radius: 12px; ' +
        'background: var(--surface); border: 1px solid var(--brand-blue); ' +
        'box-shadow: 0 4px 18px rgba(12, 79, 168, 0.08);',
    });

    var topRow = el('div', {
      style:
        'display: flex; align-items: center; justify-content: space-between; ' +
        'gap: 10px; flex-wrap: wrap; margin-bottom: 8px;',
    });

    var pillWrap = el('div', {
      style: 'display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap;',
    });

    var liveBadge = el(
      'span',
      {
        style:
          'display: inline-flex; align-items: center; gap: 6px; padding: 3px 9px; ' +
          'border-radius: 999px; background: var(--brand-blue); color: #FFFFFF; ' +
          'font-size: 10.5px; font-weight: 800; letter-spacing: 0.5px; text-transform: uppercase;',
      },
      '● Live Synced with Oneova App'
    );
    pillWrap.appendChild(liveBadge);

    var metaText =
      (doc.version || 'v1.0') +
      ' · Effective ' +
      (doc.effectiveDate || 'October 25, 2026');
    pillWrap.appendChild(
      el(
        'span',
        {
          style: 'font-size: 12px; font-weight: 700; color: var(--text-primary);',
        },
        metaText
      )
    );
    topRow.appendChild(pillWrap);

    var actionsWrap = el('div', {
      className: 'no-print',
      style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;',
    });

    var askOvaLink = el(
      'a',
      {
        href: '/?ask=1',
        style:
          'font-size: 11.5px; font-weight: 700; color: var(--brand-pink); text-decoration: none;',
      },
      '✨ Ask Ova AI Assistant →'
    );
    actionsWrap.appendChild(askOvaLink);

    var editLink = el(
      'a',
      {
        href: '/?admin=1',
        style:
          'font-size: 11.5px; font-weight: 700; color: var(--text-muted); text-decoration: none;',
      },
      '✎ Admin CMS'
    );
    actionsWrap.appendChild(editLink);
    topRow.appendChild(actionsWrap);
    box.appendChild(topRow);

    if (doc.inShort) {
      var shortP = el('p', {
        style:
          'margin: 0 0 8px 0; font-size: 13.2px; line-height: 1.55; color: var(--text-secondary);',
      });
      shortP.appendChild(el('strong', null, 'Live Executive Summary: '));
      shortP.appendChild(document.createTextNode(doc.inShort));
      box.appendChild(shortP);
    }

    if (doc.changeNote) {
      box.appendChild(
        el(
          'div',
          {
            style:
              'font-size: 11.5px; color: var(--text-muted); margin-bottom: 8px;',
          },
          'Latest update note: ' + doc.changeNote
        )
      );
    }

    var sections = Array.isArray(doc.sections) ? doc.sections : [];
    if (sections.length > 0) {
      var details = el('details', {
        style:
          'margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border);',
      });
      var summary = el(
        'summary',
        {
          style:
            'cursor: pointer; font-size: 12.2px; font-weight: 700; color: var(--brand-blue); user-select: none;',
        },
        'View Live Synchronized Clauses & Highlights (' +
          sections.length +
          ' sections)'
      );
      details.appendChild(summary);

      var secWrap = el('div', { style: 'padding-top: 10px;' });
      sections.forEach(function (sec) {
        if (!sec || typeof sec !== 'object') return;
        var card = el('div', {
          style:
            'padding: 10px 12px; margin-bottom: 8px; border-radius: 8px; ' +
            'background: var(--bg); border: 1px solid var(--border);',
        });
        if (sec.heading) {
          card.appendChild(
            el(
              'div',
              {
                style:
                  'font-size: 13px; font-weight: 800; color: var(--text-primary); margin-bottom: 4px;',
              },
              sec.heading
            )
          );
        }
        if (sec.summary) {
          card.appendChild(
            el(
              'p',
              {
                style:
                  'margin: 0 0 6px 0; font-size: 12.6px; color: var(--text-secondary);',
              },
              sec.summary
            )
          );
        }
        if (sec.callout) {
          card.appendChild(
            el(
              'div',
              {
                style:
                  'padding: 6px 10px; margin-bottom: 6px; border-left: 3px solid var(--brand-pink); ' +
                  'background: var(--surface); border-radius: 6px; font-size: 12px; color: var(--text-primary);',
              },
              sec.callout
            )
          );
        }
        if (Array.isArray(sec.bullets) && sec.bullets.length > 0) {
          var ul = el('ul', {
            style: 'margin: 4px 0 0 18px; font-size: 12.4px; color: var(--text-secondary);',
          });
          sec.bullets.forEach(function (b) {
            if (typeof b === 'string' && b.trim()) {
              ul.appendChild(el('li', { style: 'margin-bottom: 3px;' }, b));
            }
          });
          card.appendChild(ul);
        }
        secWrap.appendChild(card);
      });
      details.appendChild(secWrap);
      box.appendChild(details);
    }

    if (doc.htmlOverride && typeof doc.htmlOverride === 'string' && doc.htmlOverride.trim()) {
      var customWrap = el('div', {
        style:
          'margin-top: 10px; padding: 12px; border-radius: 8px; background: var(--bg); border: 1px solid var(--border);',
      });
      customWrap.innerHTML = doc.htmlOverride;
      box.appendChild(customWrap);
    }

    shell.insertBefore(box, shell.firstChild);
  }

  var endpoint =
    'https://firestore.googleapis.com/v1/projects/' +
    PROJECT_ID +
    '/databases/(default)/documents/platform_cms_docs/' +
    encodeURIComponent(docId);

  fetch(endpoint, { method: 'GET', headers: { Accept: 'application/json' } })
    .then(function (res) {
      if (!res.ok) return null;
      return res.json();
    })
    .then(function (json) {
      if (!json || !json.fields) return;
      var parsed = decodeDoc(json);
      if (parsed.isPublished === false) return;
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
          renderLiveBanner(parsed);
        });
      } else {
        renderLiveBanner(parsed);
      }
    })
    .catch(function () {
      // Silent offline fallback: full static statutory document remains visible
    });
})();
