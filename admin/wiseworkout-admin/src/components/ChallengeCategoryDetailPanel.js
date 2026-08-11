import React, { useState, useEffect } from 'react';
import DetailDrawer from './ui/DetailDrawer';
import { METRIC_TYPES, validateCategoryForm } from '../utils/challengeUtils';

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

function ChallengeCategoryDetailPanel({ category, startInEdit, usageCount, onClose, onSave, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const categoryId = category ? category.id : null;

  const startEdit = React.useCallback(() => {
    setForm({
      name: category.name || '',
      unit: category.unit || '',
      metricType: METRIC_TYPES.includes(category.metricType) ? category.metricType : METRIC_TYPES[0],
      minGoal: category.minGoal ?? '',
      maxGoal: category.maxGoal ?? '',
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  }, [category]);

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    if (startInEdit && category) startEdit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [categoryId]);

  if (!category) return null;

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    const validationError = validateCategoryForm(form);
    if (validationError) { setError(validationError); return; }

    const changes = {};
    if (form.name.trim() !== (category.name || '')) changes.name = form.name.trim();
    if (form.unit.trim() !== (category.unit || '')) changes.unit = form.unit.trim();
    if (form.metricType !== category.metricType) changes.metricType = form.metricType;
    const newMin = Number(form.minGoal);
    if (newMin !== category.minGoal) changes.minGoal = newMin;
    const newMax = Number(form.maxGoal);
    if (newMax !== category.maxGoal) changes.maxGoal = newMax;

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');
    try {
      await onSave(category.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Category updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error(err);
      const detail = err && err.code ? ` (${err.code})` : '';
      setError(`Failed to update category. Please try again.${detail}`);
    }
    setSaving(false);
  };

  return (
    <DetailDrawer
      title="Category Detail"
      open={Boolean(category)}
      onClose={onClose}
      viewportLocked
      actions={
        !isEditing ? (
          <button className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={startEdit}>
            Edit
          </button>
        ) : null
      }
      footer={
        isEditing ? (
          <div className="wwa-cell-actions" style={{ width: '100%', justifyContent: 'space-between' }}>
            <button className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
            <button className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
              Cancel
            </button>
          </div>
        ) : (
          <div className="wwa-cell-actions" style={{ width: '100%' }}>
            <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete(category)}>
              Delete
            </button>
          </div>
        )
      }
    >
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
            <label className="wwa-field-label">Category Name</label>
            <input
              className="wwa-input"
              value={form.name}
              onChange={e => setForm(prev => ({ ...prev, name: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Unit</label>
            <input
              className="wwa-input"
              value={form.unit}
              onChange={e => setForm(prev => ({ ...prev, unit: e.target.value }))}
              placeholder="e.g. km"
            />
          </div>
          <div>
            <label className="wwa-field-label">Metric Type</label>
            <select
              className="wwa-select"
              value={form.metricType}
              onChange={e => setForm(prev => ({ ...prev, metricType: e.target.value }))}
            >
              {METRIC_TYPES.map(mt => <option key={mt} value={mt}>{mt}</option>)}
            </select>
          </div>
          <div>
            <label className="wwa-field-label">Minimum Goal</label>
            <input
              type="number"
              min="0"
              className="wwa-input"
              value={form.minGoal}
              onChange={e => setForm(prev => ({ ...prev, minGoal: e.target.value }))}
            />
          </div>
          <div>
            <label className="wwa-field-label">Maximum Goal</label>
            <input
              type="number"
              min="0"
              className="wwa-input"
              value={form.maxGoal}
              onChange={e => setForm(prev => ({ ...prev, maxGoal: e.target.value }))}
            />
          </div>
        </div>
      ) : (
        <div style={{ marginBottom: 8 }}>
          <DetailRow label="Category ID" value={<span style={monoStyle}>{category.id}</span>} />
          <DetailRow label="Name" value={category.name || '—'} />
          <DetailRow label="Unit" value={category.unit || '—'} />
          <DetailRow label="Metric Type" value={category.metricType || '—'} />
          <DetailRow label="Minimum Goal" value={category.minGoal ?? '—'} />
          <DetailRow label="Maximum Goal" value={category.maxGoal ?? '—'} />
          <DetailRow label="Used By" value={`${usageCount} challenge${usageCount === 1 ? '' : 's'}`} />
        </div>
      )}
    </DetailDrawer>
  );
}

export default ChallengeCategoryDetailPanel;
