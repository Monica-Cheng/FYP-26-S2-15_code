import React, { useState, useEffect } from 'react';

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

function InjuryDetailPanel({ injury, startInEdit, onClose, onSave, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const injuryId = injury ? injury.id : null;

  const startEdit = React.useCallback(() => {
    setForm({
      name: injury.name || '',
      bodyPart: injury.bodyPart || '',
      description: injury.description || '',
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  }, [injury]);

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    if (startInEdit && injury) startEdit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [injuryId]);

  if (!injury) return null;

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    if (!form.name.trim()) { setError('Name is required.'); return; }
    if (!form.bodyPart.trim()) { setError('Body Part is required.'); return; }
    if (!form.description.trim()) { setError('Description is required.'); return; }

    const changes = {};
    if (form.name.trim() !== (injury.name || '')) changes.name = form.name.trim();
    if (form.bodyPart.trim() !== (injury.bodyPart || '')) changes.bodyPart = form.bodyPart.trim();
    if (form.description.trim() !== (injury.description || '')) changes.description = form.description.trim();

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(injury.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Injury category updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      setError('Failed to update injury category. Please try again.');
    }
    setSaving(false);
  };

  return (
    <div className="wwa-panel">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
        <div className="wwa-panel-title" style={{ marginBottom: 0 }}>Injury Detail</div>
        <div style={{ display: 'flex', gap: 8 }}>
          {!isEditing && (
            <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={startEdit}>
              Edit
            </button>
          )}
          <button className="wwa-panel-close" onClick={onClose} aria-label="Close injury detail">✕</button>
        </div>
      </div>

      {successMsg && (
        <div className="wwa-status-pill" style={{ marginBottom: 16 }}>
          <span className="wwa-status-dot" />
          {successMsg}
        </div>
      )}
      {error && <div className="wwa-alert-error" style={{ marginBottom: 16 }}>{error}</div>}

      {isEditing ? (
        <div className="wwa-form-grid" style={{ marginBottom: 4 }}>
          <div>
            <label className="wwa-field-label">Name</label>
            <input
              className="wwa-input"
              value={form.name}
              onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
              placeholder="e.g. Lower Back"
            />
          </div>
          <div>
            <label className="wwa-field-label">Body Part</label>
            <input
              className="wwa-input"
              value={form.bodyPart}
              onChange={e => setForm(prev => ({ ...prev, bodyPart: e.target.value }))}
              placeholder="e.g. Lower Back"
            />
          </div>
          <div className="wwa-field-full">
            <label className="wwa-field-label">Description</label>
            <input
              className="wwa-input"
              value={form.description}
              onChange={e => setForm(prev => ({ ...prev, description: e.target.value }))}
              placeholder="e.g. Pain or discomfort in the lower back region"
            />
          </div>
        </div>
      ) : (
        <div style={{ marginBottom: 8 }}>
          <DetailRow label="Name" value={injury.name || '—'} />
          <DetailRow label="Body Part" value={injury.bodyPart || '—'} />
          <DetailRow label="Description" value={injury.description || '—'} />
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
          <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete(injury.id)}>
            Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default InjuryDetailPanel;
