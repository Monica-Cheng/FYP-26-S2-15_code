import React, { useEffect, useState } from 'react';
import DetailDrawer from './ui/DetailDrawer';
import FormSection from './ui/FormSection';
import FormField from './ui/FormField';
import { getCallableErrorMessage } from '../utils/planUtils';

function InjuryDetailStyles() {
  return (
    <style>{`
      .wwid-summary {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .wwid-summary__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.25;
      }
      .wwid-summary__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwid-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwid-footer {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwid-message-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwid-message-stack .wwa-status-pill,
      .wwid-message-stack .wwa-alert-error {
        margin: 0;
      }
      .wwid-description {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwid-readonly-note {
        margin-top: -4px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
    `}</style>
  );
}

function DetailRow({ label, value, multiline = false }) {
  if (value === undefined || value === null || value === '') return null;

  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      {multiline ? <div className="wwid-description">{value}</div> : <span className="wwa-detail-value">{value}</span>}
    </div>
  );
}

function formatMeta(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function InjuryDetailPanel({ injury, startInEdit, onClose, onSave, onEdit, onDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const injuryId = injury ? injury.id : null;

  useEffect(() => {
    setError('');
    setSuccessMsg('');

    if (!injury) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    if (startInEdit) {
      setForm({
        description: injury.description || '',
      });
      setIsEditing(true);
    } else {
      setIsEditing(false);
      setForm(null);
    }
  }, [injuryId, startInEdit, injury]);

  if (!injury) return null;

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    if (!form.description.trim()) {
      setError('Description is required.');
      return;
    }
    if (form.description.trim().length > 500) {
      setError('Description cannot exceed 500 characters.');
      return;
    }

    const changes = {};
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
      setError(getCallableErrorMessage(err, 'Failed to update injury category. Please try again.'));
    }

    setSaving(false);
  };

  const summary = (
    <div className="wwid-summary">
      <div className="wwid-summary__title">{injury.name || 'Unnamed injury'}</div>
      {injury.bodyPart ? <div className="wwid-summary__meta">{injury.bodyPart}</div> : null}
    </div>
  );

  return (
    <>
      <InjuryDetailStyles />
      <DetailDrawer
        title="Injury"
        open={Boolean(injury)}
        onClose={onClose}
        actions={
          !isEditing && onEdit ? (
            <button type="button" className="wwa-btn wwa-btn-secondary wwa-btn-sm" onClick={() => onEdit(injury)}>
              Edit
            </button>
          ) : null
        }
        summary={summary}
        footer={
          isEditing ? (
            <div className="wwid-footer">
              <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
                Cancel
              </button>
              <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          ) : onDelete ? (
            <button type="button" className="wwa-btn wwa-btn-danger" onClick={() => onDelete(injury)}>
              Delete
            </button>
          ) : null
        }
      >
        {(successMsg || error) ? (
          <div className="wwid-message-stack">
            {successMsg ? (
              <div className="wwa-status-pill">
                <span className="wwa-status-dot" />
                {successMsg}
              </div>
            ) : null}
            {error ? <div className="wwa-alert-error">{error}</div> : null}
          </div>
        ) : null}

        {isEditing ? (
          <div className="wwid-form">
            <FormSection title="Injury Details" columns={2}>
              <FormField label="Name" labelFor="edit-injury-name">
                <input
                  id="edit-injury-name"
                  className="wwa-input"
                  value={injury.name || ''}
                  disabled
                  readOnly
                />
              </FormField>

              <FormField label="Body Part" labelFor="edit-injury-body-part">
                <input
                  id="edit-injury-body-part"
                  className="wwa-input"
                  value={injury.bodyPart || ''}
                  disabled
                  readOnly
                />
              </FormField>

              <div className="wwid-readonly-note">
                Name and body part cannot be changed after creation because exercises and user injury records reference this category.
              </div>

              <FormField label="Description" labelFor="edit-injury-description" required fullWidth>
                <input
                  id="edit-injury-description"
                  className="wwa-input"
                  value={form.description}
                  onChange={(event) => setForm((prev) => ({ ...prev, description: event.target.value }))}
                  placeholder="e.g. Pain or discomfort in the lower back region"
                />
              </FormField>
            </FormSection>
          </div>
        ) : (
          <>
            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Details</div>
              <DetailRow label="Name" value={injury.name || '—'} />
              <DetailRow label="Body Part" value={injury.bodyPart || '—'} />
              <DetailRow label="Description" value={injury.description || '—'} multiline />
            </section>

            {(injury.createdAt || injury.updatedAt) ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Metadata</div>
                <DetailRow label="Created" value={formatMeta(injury.createdAt)} />
                <DetailRow label="Updated" value={formatMeta(injury.updatedAt)} />
              </section>
            ) : null}
          </>
        )}
      </DetailDrawer>
    </>
  );
}

export default InjuryDetailPanel;
