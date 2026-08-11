import React, { useEffect, useState } from 'react';
import DetailDrawer from './ui/DetailDrawer';
import FormSection from './ui/FormSection';
import FormField from './ui/FormField';
import ConditionsEditor from './ConditionsEditor';
import ImageThumb from './ui/ImageThumb';
import { formatDate } from '../utils/dateUtils';
import {
  normalizeConditionsForSave,
  normalizeConditionValue,
  validateBadgeForm,
  getBadgeCallableErrorMessage,
} from '../utils/badgeUtils';

function BadgeDetailStyles() {
  return (
    <style>{`
      .wwbd-summary {
        display: flex;
        gap: 16px;
        align-items: flex-start;
      }
      .wwbd-summary__media {
        width: 88px;
        height: 88px;
        border-radius: 14px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-card);
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
        flex-shrink: 0;
      }
      .wwbd-summary__media img {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
      }
      .wwbd-summary__fallback {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
        background: var(--ww-elevated);
      }
      .wwbd-summary__content {
        display: flex;
        flex-direction: column;
        gap: 8px;
        min-width: 0;
      }
      .wwbd-summary__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.25;
      }
      .wwbd-description {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwbd-conditions {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwbd-condition {
        display: flex;
        flex-direction: column;
        gap: 10px;
        padding-top: 14px;
        border-top: 1px solid var(--ww-divider);
      }
      .wwbd-condition:first-child {
        padding-top: 0;
        border-top: 0;
      }
      .wwbd-condition__title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwbd-form {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbd-footer {
        display: flex;
        justify-content: flex-end;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwbd-message-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwbd-message-stack .wwa-status-pill,
      .wwbd-message-stack .wwa-alert-error {
        margin: 0;
      }
      @media (max-width: 640px) {
        .wwbd-summary {
          flex-direction: column;
        }
      }
    `}</style>
  );
}

function DetailRow({ label, value }) {
  if (value === undefined || value === null || value === '') return null;

  return (
    <div className="wwa-detail-row">
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

function BadgeDetailPanel({ badge, startInEdit, onClose, onSave, onEdit, onDelete, supportedStatTypes }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const badgeId = badge ? badge.id : null;

  useEffect(() => {
    setError('');
    setSuccessMsg('');

    if (!badge) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    if (startInEdit) {
      setForm({
        name: badge.name || '',
        description: badge.description || '',
        imageUrl: badge.imageUrl || '',
        conditions:
          Array.isArray(badge.conditions) && badge.conditions.length > 0
            ? badge.conditions.map((condition) => ({ statType: condition?.statType || '', value: condition?.value ?? '' }))
            : [{ statType: '', value: '' }],
      });
      setIsEditing(true);
    } else {
      setIsEditing(false);
      setForm(null);
    }
  }, [badgeId, startInEdit, badge]);

  if (!badge) return null;

  const normalizedConditions = Array.isArray(badge.conditions) ? badge.conditions : [];

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    const validationError = validateBadgeForm(form, supportedStatTypes);
    if (validationError) {
      setError(validationError);
      return;
    }

    const nextConditions = normalizeConditionsForSave(form.conditions);
    const changes = {};

    if (form.name.trim() !== (badge.name || '')) changes.name = form.name.trim();
    if (form.description.trim() !== (badge.description || '')) changes.description = form.description.trim();
    if (form.imageUrl.trim() !== (badge.imageUrl || '')) changes.imageUrl = form.imageUrl.trim();
    if (JSON.stringify(nextConditions) !== JSON.stringify(badge.conditions || [])) {
      changes.conditions = nextConditions;
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
      setError(getBadgeCallableErrorMessage(err, 'Failed to update badge. Please try again.'));
    } finally {
      setSaving(false);
    }
  };

  const summary = (
    <div className="wwbd-summary">
      <div className="wwbd-summary__media" aria-hidden="true">
        <ImageThumb url={badge.imageUrl} size={88} icon="🏅" />
      </div>
      <div className="wwbd-summary__content">
        <div className="wwbd-summary__title">{badge.name || 'Unnamed badge'}</div>
      </div>
    </div>
  );

  return (
    <>
      <BadgeDetailStyles />
      <DetailDrawer
        title="Badge"
        open={Boolean(badge)}
        onClose={onClose}
        actions={
          !isEditing && onEdit ? (
            <button
              type="button"
              className="wwa-btn wwa-btn-sm wwa-btn-secondary"
              onClick={() => onEdit(badge)}
            >
              Edit
            </button>
          ) : null
        }
        summary={summary}
        footer={
          isEditing ? (
            <div className="wwbd-footer">
              <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
                Cancel
              </button>
              <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          ) : onDelete ? (
            <div className="wwbd-footer">
              <button type="button" className="wwa-btn wwa-btn-danger" onClick={() => onDelete(badge)}>
                Delete
              </button>
            </div>
          ) : null
        }
      >
        {(successMsg || error) ? (
          <div className="wwbd-message-stack">
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
          <div className="wwbd-form">
            <FormSection title="Basic Information" columns={2}>
              <FormField label="Badge Name" labelFor="badge-name" required>
                <input
                  id="badge-name"
                  className="wwa-input"
                  value={form.name}
                  onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                  placeholder="e.g. Distance Runner"
                  maxLength={100}
                />
              </FormField>

              <FormField label="Image URL" labelFor="badge-image-url">
                <input
                  id="badge-image-url"
                  className="wwa-input"
                  value={form.imageUrl}
                  onChange={(event) => setForm((prev) => ({ ...prev, imageUrl: event.target.value }))}
                  placeholder="https://…"
                />
              </FormField>

              <FormField label="Description" labelFor="badge-description" required fullWidth>
                <input
                  id="badge-description"
                  className="wwa-input"
                  value={form.description}
                  onChange={(event) => setForm((prev) => ({ ...prev, description: event.target.value }))}
                  placeholder="e.g. Run 50km total"
                  maxLength={500}
                />
              </FormField>
            </FormSection>

            <FormSection title="Earning Conditions" columns={1}>
              <ConditionsEditor
                conditions={form.conditions}
                onChange={(next) => setForm((prev) => ({ ...prev, conditions: next }))}
                disabled={saving}
                layout="stacked"
                supportedStatTypes={supportedStatTypes}
              />
            </FormSection>
          </div>
        ) : (
          <>
            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Overview</div>
              <DetailRow label="Badge ID" value={badge.id || '—'} />
            </section>

            {badge.description ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Description</div>
                <div className="wwbd-description">{badge.description}</div>
              </section>
            ) : null}

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Earning Conditions</div>
              <div className="wwbd-conditions">
                {normalizedConditions.length > 0 ? (
                  normalizedConditions.map((condition, index) => (
                    <div key={`${badge.id}-condition-${index}`} className="wwbd-condition">
                      <div className="wwbd-condition__title">Condition {index + 1}</div>
                      <DetailRow label="Stat Type" value={condition?.statType || '—'} />
                      <DetailRow label="Value" value={normalizeConditionValue(condition?.value) ?? '—'} />
                    </div>
                  ))
                ) : (
                  <div className="wwa-help-text">No earning conditions configured.</div>
                )}
              </div>
            </section>

            {(badge.createdAt || badge.updatedAt || badge.createdByAdminUid || badge.updatedByAdminUid) ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Audit</div>
                <DetailRow label="Created At" value={badge.createdAt ? formatDate(badge.createdAt) : undefined} />
                <DetailRow label="Updated At" value={badge.updatedAt ? formatDate(badge.updatedAt) : undefined} />
                <DetailRow label="Created By" value={badge.createdByAdminUid || undefined} />
                <DetailRow label="Updated By" value={badge.updatedByAdminUid || undefined} />
              </section>
            ) : null}
          </>
        )}
      </DetailDrawer>
    </>
  );
}

export default BadgeDetailPanel;
