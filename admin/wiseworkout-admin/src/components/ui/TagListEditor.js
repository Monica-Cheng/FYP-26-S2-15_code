import React, { useState } from 'react';
import { Plus, X } from 'lucide-react';

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
    <div className="wwa-tag-editor">
      {tags.length > 0 && (
        <div className="wwa-tag-editor__chips">
          {tags.map((tag, i) => (
            <span key={i} className="wwa-badge wwa-badge-neutral wwa-tag-editor__chip">
              {tag}
              <button
                type="button"
                onClick={() => removeTag(i)}
                disabled={disabled}
                aria-label={`Remove ${tag}`}
                className="wwa-tag-editor__remove"
              >
                <X aria-hidden="true" size={12} strokeWidth={2} />
              </button>
            </span>
          ))}
        </div>
      )}
      <div className="wwa-tag-editor__input-row">
        <input
          className="wwa-input"
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); addTag(); } }}
          placeholder={placeholder}
          disabled={disabled}
        />
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addTag} disabled={disabled}>
          <Plus aria-hidden="true" size={14} strokeWidth={2} />
          Add
        </button>
      </div>
    </div>
  );
}

export default TagListEditor;
