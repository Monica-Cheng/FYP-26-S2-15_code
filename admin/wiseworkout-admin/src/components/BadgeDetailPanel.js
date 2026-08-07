import React, { useState, useEffect } from 'react';
import ImageThumb from './ui/ImageThumb';
import ConditionsEditor from './ConditionsEditor';
import {
  formatConditions, validateConditions, normalizeConditionsForSave, isValidImageUrl,
} from '../utils/badgeUtils';

const monoStyle = { fontFamily: 'Consolas, Menlo, monospace', fontSize: '12px' };

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

function BadgeDetailPanel({ badge, startInEdit, onClose, onSave, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const badgeId = badge ? badge.id : null;

  // Handles both missing `conditions` and legacy numeric-string `value`
  // fields on older documents by feeding them straight into text/number
  // inputs, which coerce either representation to a string automatically.
  const startEdit = React.useCallback(() => {
    setForm({
      name: badge.name || '',
      description: badge.description || '',
      imageUrl: badge.imageUrl || '',
      conditions: Array.isArray(badge.conditions) && badge.conditions.length > 0
        ? badge.conditions.map(c => ({ statType: c?.statType || '', value: c?.value ?? '' }))
        : [{ statType: '', value: '' }],
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  }, [badge]);

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    if (startInEdit && badge) startEdit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [badgeId]);

  if (!badge) return null;

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    if (!form.name.trim()) { setError('Badge Name is required.'); return; }
    if (!form.description.trim()) { setError('Description is required.'); return; }
    if (form.imageUrl.trim() && !isValidImageUrl(form.imageUrl)) {
      setError('Image URL must start with http:// or https://.');
      return;
    }
    const conditionsError = validateConditions(form.conditions);
    if (conditionsError) { setError(conditionsError); return; }

    const normalizedConditions = normalizeConditionsForSave(form.conditions);

    // Partial update — only fields that actually changed are sent, so an
    // in-progress edit never clobbers fields this form doesn't touch.
    const changes = {};
    if (form.name.trim() !== (badge.name || '')) changes.name = form.name.trim();
    if (form.description.trim() !== (badge.description || '')) changes.description = form.description.trim();
    if (form.imageUrl.trim() !== (badge.imageUrl || '')) changes.imageUrl = form.imageUrl.trim();
    if (JSON.stringify(normalizedConditions) !== JSON.stringify(badge.conditions || [])) {
      changes.conditions = normalizedConditions;
    }

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(badge.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Badge updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      setError(`Failed to update badge. Please try again.${detail}`);
    }
    setSaving(false);
  };

  const conditionTexts = formatConditions(badge.conditions);

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Badge Detail</div>
        <div style={{ display: 'flex', gap: 8 }}>
          {!isEditing && (
            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={startEdit}>
              Edit
            </button>
          )}
          <button className="wwa-panel-close" onClick={onClose} aria-label="Close badge detail">✕</button>
        </div>
      </div>

      {successMsg && (
        <div className="wwa-status-pill" style={{ marginBottom: 16 }}>
          <span className="wwa-status-dot" />
          {successMsg}
        </div>
      )}
      {error && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>}

      {!isEditing && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 20 }}>
          <ImageThumb url={badge.imageUrl} size={56} />
          <div>
            <div style={{ fontSize: '16px', fontWeight: 700, color: '#111827' }}>{badge.name || 'Unnamed badge'}</div>
            <div style={{ fontSize: 13, color: '#9ca3af', marginTop: 2 }}>{badge.description || '—'}</div>
          </div>
        </div>
      )}

      {isEditing ? (
        <div style={{ marginBottom: 4 }}>
          <div className="wwa-form-grid" style={{ marginBottom: 16 }}>
            <div>
              <label className="wwa-field-label">Badge Name</label>
              <input
                className="wwa-input"
                value={form.name}
                onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
                placeholder="e.g. Distance Runner"
              />
            </div>
            <div>
              <label className="wwa-field-label">Image URL</label>
              <input
                className="wwa-input"
                value={form.imageUrl}
                onChange={e => setForm(prev => ({ ...prev, imageUrl: e.target.value }))}
                placeholder="https://…"
              />
            </div>
            <div className="wwa-field-full">
              <label className="wwa-field-label">Description</label>
              <input
                className="wwa-input"
                value={form.description}
                onChange={e => setForm(prev => ({ ...prev, description: e.target.value }))}
                placeholder="e.g. Run 50km total"
              />
            </div>
          </div>
          <ConditionsEditor
            conditions={form.conditions}
            onChange={next => setForm(prev => ({ ...prev, conditions: next }))}
            disabled={saving}
          />
        </div>
      ) : (
        <div style={{ marginBottom: 8 }}>
          <DetailRow label="Badge ID" value={<span style={monoStyle}>{badge.id}</span>} />
          <DetailRow label="Name" value={badge.name || '—'} />
          <DetailRow label="Description" value={badge.description || '—'} />
          <DetailRow label="Image URL" value={badge.imageUrl ? <span style={monoStyle}>{badge.imageUrl}</span> : undefined} />
          <div className="wwa-detail-row" style={{ alignItems: 'flex-start' }}>
            <span className="wwa-detail-label">Conditions</span>
            <div style={{ textAlign: 'right' }}>
              {conditionTexts === '—' ? (
                <span className="wwa-detail-value">—</span>
              ) : (
                conditionTexts.map((text, i) => (
                  <div key={i} className="wwa-detail-value" style={{ marginBottom: i === conditionTexts.length - 1 ? 0 : 4 }}>
                    {text}
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {isEditing ? (
        <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
          <button className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
          <button className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
            Cancel
          </button>
        </div>
      ) : (
        <div className="wwa-cell-actions" style={{ marginTop: 8 }}>
          <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete(badge.id)}>
            Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default BadgeDetailPanel;
