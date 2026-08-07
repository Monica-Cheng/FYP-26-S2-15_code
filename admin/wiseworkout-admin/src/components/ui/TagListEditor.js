import React, { useState } from 'react';

// Generic chip/tag input — add via Enter or the Add button, remove via the
// chip's ✕. Dedup/trim/empty-value rules are the caller's responsibility
// (via onChange), since what counts as a duplicate can be domain-specific.
function TagListEditor({ tags, onChange, disabled, placeholder = 'Add a value…' }) {
  const [draft, setDraft] = useState('');

  const addTag = () => {
    const value = draft.trim();
    if (!value) return;
    onChange([...tags, value]);
    setDraft('');
  };

  const removeTag = (index) => onChange(tags.filter((_, i) => i !== index));

  return (
    <div>
      {tags.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 8 }}>
          {tags.map((tag, i) => (
            <span key={i} className="wwa-badge wwa-badge-neutral" style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              {tag}
              <button
                type="button"
                onClick={() => removeTag(i)}
                disabled={disabled}
                aria-label={`Remove ${tag}`}
                style={{ border: 'none', background: 'none', cursor: 'pointer', color: '#9ca3af', fontSize: 12, padding: 0, lineHeight: 1 }}
              >
                ✕
              </button>
            </span>
          ))}
        </div>
      )}
      <div style={{ display: 'flex', gap: 8 }}>
        <input
          className="wwa-input"
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); addTag(); } }}
          placeholder={placeholder}
          disabled={disabled}
        />
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addTag} disabled={disabled}>
          Add
        </button>
      </div>
    </div>
  );
}

export default TagListEditor;
