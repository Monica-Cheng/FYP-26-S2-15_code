import React, { useEffect, useState } from 'react';
import { EyeOff, Pencil, Trash2 } from 'lucide-react';
import Badge from './ui/Badge';
import DetailDrawer from './ui/DetailDrawer';
import FormSection from './ui/FormSection';
import FormField from './ui/FormField';
import { formatDate } from '../utils/dateUtils';

const NUTRITION_FIELDS = [
  { key: 'calories', label: 'Calories', suffix: '' },
  { key: 'proteinG', label: 'Protein', suffix: ' g' },
  { key: 'carbsG', label: 'Carbs', suffix: ' g' },
  { key: 'fatG', label: 'Fat', suffix: ' g' },
];

const typeTone = (type) => {
  const value = (type || '').toLowerCase();
  if (value.includes('meal')) return 'brand';
  if (value.includes('workout')) return 'neutral';
  return 'neutral';
};

const statusTone = (isHidden) => (isHidden ? 'warning' : 'success');

const isWorkoutPost = (post) => (post?.type || '').toLowerCase() === 'workout';

const postTitle = (post) => {
  if (isWorkoutPost(post)) {
    return post?.sessionName || post?.caption || 'Workout session';
  }

  return post?.foodName || post?.caption || 'Untitled post';
};

function PostDetailStyles() {
  return (
    <style>{`
      .wwpd-summary {
        display: flex;
        gap: 16px;
        align-items: flex-start;
      }
      .wwpd-summary__media {
        width: 132px;
        aspect-ratio: 1 / 1;
        border-radius: 12px;
        overflow: hidden;
        border: 1px solid var(--ww-divider);
        background: var(--ww-elevated);
        flex-shrink: 0;
      }
      .wwpd-summary__media img {
        width: 100%;
        height: 100%;
        display: block;
        object-fit: cover;
      }
      .wwpd-summary__content {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwpd-summary__title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.25;
      }
      .wwpd-summary__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwpd-summary__badges {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwpd-text-block {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
      }
      .wwpd-identifier {
        font-family: Consolas, Menlo, monospace;
        font-size: 12px;
      }
      .wwpd-footer {
        display: flex;
        gap: 10px;
        justify-content: flex-end;
        flex-wrap: wrap;
      }
      .wwpd-message-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwpd-message-stack .wwa-status-pill,
      .wwpd-message-stack .wwa-alert-error {
        margin: 0;
      }
      .wwpd-media-preview {
        margin-top: 12px;
        border-radius: 14px;
        overflow: hidden;
        border: 1px solid var(--ww-divider);
        background: var(--ww-elevated);
      }
      .wwpd-media-preview img {
        width: 100%;
        display: block;
        object-fit: cover;
      }
      @media (max-width: 640px) {
        .wwpd-summary {
          flex-direction: column;
        }
        .wwpd-summary__media {
          width: 100%;
          max-width: 240px;
        }
      }
    `}</style>
  );
}

function DetailRow({ label, value, className = '' }) {
  if (value === undefined || value === null || value === '') return null;

  return (
    <div className={`wwa-detail-row ${className}`.trim()}>
      <span className="wwa-detail-label">{label}</span>
      <span className="wwa-detail-value">{value}</span>
    </div>
  );
}

function toImageSrc(imageBase64) {
  if (!imageBase64 || typeof imageBase64 !== 'string') return null;
  if (imageBase64.startsWith('data:image')) return imageBase64;
  return `data:image/jpeg;base64,${imageBase64}`;
}

function formatElapsedSeconds(value) {
  if (!Number.isFinite(Number(value))) return null;
  const totalSeconds = Math.max(0, Number(value));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  if (minutes > 0 && seconds > 0) return `${minutes} min ${seconds} sec`;
  if (minutes > 0) return `${minutes} min`;
  return `${seconds} sec`;
}

function formatVolume(value) {
  if (!Number.isFinite(Number(value))) return null;
  return `${Number(value)} kg`;
}

function PostDetailPanel({ post, editNonce = 0, onClose, onSave, onRequestToggleHidden, onRequestDelete }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [imageFailed, setImageFailed] = useState(false);
  const postId = post ? post.id : null;

  function openEditor() {
    if (!post) return;

    setForm({
      foodName: post.foodName || '',
      caption: post.caption || '',
      calories: post.calories ?? '',
      proteinG: post.proteinG ?? '',
      carbsG: post.carbsG ?? '',
      fatG: post.fatG ?? '',
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  }

  useEffect(() => {
    setIsEditing(false);
    setForm(null);
    setError('');
    setSuccessMsg('');
    setImageFailed(false);
  }, [postId]);

  useEffect(() => {
    if (!post || editNonce === 0) return;
    setForm({
      foodName: post.foodName || '',
      caption: post.caption || '',
      calories: post.calories ?? '',
      proteinG: post.proteinG ?? '',
      carbsG: post.carbsG ?? '',
      fatG: post.fatG ?? '',
    });
    setError('');
    setSuccessMsg('');
    setIsEditing(true);
  }, [editNonce, post]);

  if (!post) return null;

  const workoutPost = isWorkoutPost(post);
  const isHidden = !!post.isHidden;
  const imageSrc = toImageSrc(post.imageBase64);
  const showImage = Boolean(imageSrc && !imageFailed);
  const title = postTitle(post);
  const nutritionFields = NUTRITION_FIELDS.filter((field) => post[field.key] !== undefined && post[field.key] !== null);

  const cancelEdit = () => {
    setIsEditing(false);
    setForm(null);
    setError('');
  };

  const handleSave = async () => {
    for (const field of NUTRITION_FIELDS) {
      const raw = form[field.key];
      if (raw !== '' && Number(raw) < 0) {
        setError(`${field.label} cannot be negative.`);
        return;
      }
    }

    const changes = {};

    if (!workoutPost && form.foodName.trim() !== (post.foodName || '')) {
      changes.foodName = form.foodName.trim();
    }
    if (form.caption.trim() !== (post.caption || '')) {
      changes.caption = form.caption.trim();
    }

    if (form.calories !== '' || post.calories !== undefined) {
      const newCalories = form.calories === '' ? null : Number(form.calories);
      const oldCalories = post.calories ?? null;
      if (newCalories !== oldCalories) {
        changes.calories = newCalories;
      }
    }

    if (!workoutPost) {
      ['proteinG', 'carbsG', 'fatG'].forEach((field) => {
        const raw = form[field];
        const newValue = raw === '' ? null : Number(raw);
        const oldValue = post[field] ?? null;
        if (newValue !== oldValue) {
          changes[field] = newValue;
        }
      });
    }

    if (Object.keys(changes).length === 0) {
      setIsEditing(false);
      setForm(null);
      return;
    }

    setSaving(true);
    setError('');

    try {
      await onSave(post.id, changes);
      setIsEditing(false);
      setForm(null);
      setSuccessMsg('Post updated successfully');
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update post. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  const summary = (
    <div className="wwpd-summary">
      {showImage ? (
        <div className="wwpd-summary__media">
          <img
            src={imageSrc}
            alt={title}
            onError={() => setImageFailed(true)}
          />
        </div>
      ) : null}
      <div className="wwpd-summary__content">
        <div className="wwpd-summary__title">{title}</div>
        <div className="wwpd-summary__meta">
          {post.authorName || 'Unknown author'}
          {post.createdAt ? ` · ${formatDate(post.createdAt)}` : ''}
        </div>
        <div className="wwpd-summary__badges">
          <Badge tone={typeTone(post.type)}>{post.type || 'Post'}</Badge>
          <Badge tone={statusTone(isHidden)}>{isHidden ? 'Hidden' : 'Visible'}</Badge>
        </div>
      </div>
    </div>
  );

  const headerActions = !isEditing ? (
    <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={openEditor}>
      <Pencil aria-hidden="true" size={14} strokeWidth={2} />
      Edit
    </button>
  ) : null;

  const footer = isEditing ? (
    <div className="wwpd-footer">
      <button type="button" className="wwa-btn wwa-btn-secondary" onClick={cancelEdit} disabled={saving}>
        Cancel
      </button>
      <button type="button" className="wwa-btn wwa-btn-primary" onClick={handleSave} disabled={saving}>
        {saving ? 'Saving...' : 'Save Changes'}
      </button>
    </div>
  ) : (
    <div className="wwpd-footer">
      <button
        type="button"
        className={`wwa-btn ${isHidden ? 'wwa-btn-secondary' : 'wwa-btn-ghost'}`}
        onClick={() => onRequestToggleHidden(post.id, !isHidden)}
      >
        <EyeOff aria-hidden="true" size={16} strokeWidth={2} />
        {isHidden ? 'Unhide' : 'Hide'}
      </button>
      <button type="button" className="wwa-btn wwa-btn-danger" onClick={() => onRequestDelete(post.id)}>
        <Trash2 aria-hidden="true" size={16} strokeWidth={2} />
        Delete
      </button>
    </div>
  );

  return (
    <>
      <PostDetailStyles />
      <DetailDrawer
        title="Post"
        open={Boolean(post)}
        onClose={onClose}
        actions={headerActions}
        summary={summary}
        footer={footer}
      >
        {(successMsg || error) ? (
          <div className="wwpd-message-stack">
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
          <FormSection
            title="Edit Post"
            description={
              workoutPost
                ? 'Update the fields currently supported by the backend for workout posts.'
                : 'Update existing meal post content and nutrition values.'
            }
            columns={2}
          >
            {!workoutPost ? (
              <FormField label="Food Name" labelFor="post-food-name">
                <input
                  id="post-food-name"
                  className="wwa-input"
                  value={form.foodName}
                  onChange={(event) => setForm((prev) => ({ ...prev, foodName: event.target.value }))}
                  placeholder="Food name"
                />
              </FormField>
            ) : null}

            <FormField label="Calories" labelFor="post-calories">
              <input
                id="post-calories"
                type="number"
                min="0"
                className="wwa-input"
                value={form.calories}
                onChange={(event) => setForm((prev) => ({ ...prev, calories: event.target.value }))}
              />
            </FormField>

            <FormField label="Caption" labelFor="post-caption" fullWidth>
              <textarea
                id="post-caption"
                className="wwa-input"
                rows={4}
                value={form.caption}
                onChange={(event) => setForm((prev) => ({ ...prev, caption: event.target.value }))}
                placeholder="Caption"
              />
            </FormField>

            {!workoutPost ? (
              <>
                <FormField label="Protein (g)" labelFor="post-protein">
                  <input
                    id="post-protein"
                    type="number"
                    min="0"
                    className="wwa-input"
                    value={form.proteinG}
                    onChange={(event) => setForm((prev) => ({ ...prev, proteinG: event.target.value }))}
                  />
                </FormField>

                <FormField label="Carbs (g)" labelFor="post-carbs">
                  <input
                    id="post-carbs"
                    type="number"
                    min="0"
                    className="wwa-input"
                    value={form.carbsG}
                    onChange={(event) => setForm((prev) => ({ ...prev, carbsG: event.target.value }))}
                  />
                </FormField>

                <FormField label="Fat (g)" labelFor="post-fat">
                  <input
                    id="post-fat"
                    type="number"
                    min="0"
                    className="wwa-input"
                    value={form.fatG}
                    onChange={(event) => setForm((prev) => ({ ...prev, fatG: event.target.value }))}
                  />
                </FormField>
              </>
            ) : null}
          </FormSection>
        ) : (
          <>
            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Content</div>
              {post.caption ? (
                <div className="wwa-detail-row">
                  <span className="wwa-detail-label">Caption</span>
                  <div className="wwpd-text-block">{post.caption}</div>
                </div>
              ) : null}
              {showImage ? (
                <div className="wwpd-media-preview">
                  <img src={imageSrc} alt={title} onError={() => setImageFailed(true)} />
                </div>
              ) : null}
            </section>

            {!workoutPost ? (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Nutrition</div>
                {post.foodName ? <DetailRow label="Food Name" value={post.foodName} /> : null}
                {nutritionFields.map((field) => (
                  <DetailRow
                    key={field.key}
                    label={field.label}
                    value={`${post[field.key]}${field.suffix}`}
                  />
                ))}
              </section>
            ) : (
              <section className="wwa-detail-section">
                <div className="wwa-detail-section__title">Workout Details</div>
                {post.sessionName ? <DetailRow label="Session Name" value={post.sessionName} /> : null}
                <DetailRow label="Workout Style" value={post.isCardio ? 'Cardio' : 'Strength'} />
                {post.isCardio ? <DetailRow label="Cardio Activity" value={post.cardioActivity} /> : null}
                <DetailRow label="Elapsed Time" value={formatElapsedSeconds(post.elapsedSeconds)} />
                {!post.isCardio ? <DetailRow label="Total Sets" value={post.totalSets} /> : null}
                {!post.isCardio ? <DetailRow label="Volume" value={formatVolume(post.volume)} /> : null}
                <DetailRow label="Calories" value={post.calories} />
              </section>
            )}

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Engagement</div>
              <DetailRow label="Reactions" value={post.reactionCount ?? 0} />
              <DetailRow label="Comments" value={post.commentCount ?? 0} />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Author</div>
              <DetailRow label="Name" value={post.authorName || 'Unknown author'} />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Moderation</div>
              <DetailRow label="Status" value={isHidden ? 'Hidden' : 'Visible'} />
              <DetailRow label="Moderated At" value={formatDate(post.moderationUpdatedAt)} />
              <DetailRow
                label="Moderated By Admin UID"
                value={post.moderatedByAdminUid ? <span className="wwpd-identifier">{post.moderatedByAdminUid}</span> : null}
              />
              <DetailRow label="Admin Updated At" value={formatDate(post.adminUpdatedAt)} />
              <DetailRow
                label="Updated By Admin UID"
                value={post.updatedByAdminUid ? <span className="wwpd-identifier">{post.updatedByAdminUid}</span> : null}
              />
            </section>

            <section className="wwa-detail-section">
              <div className="wwa-detail-section__title">Technical</div>
              {post.id ? <DetailRow label="Post ID" value={<span className="wwpd-identifier">{post.id}</span>} /> : null}
              {post.uid ? <DetailRow label="Author UID" value={<span className="wwpd-identifier">{post.uid}</span>} /> : null}
            </section>
          </>
        )}
      </DetailDrawer>
    </>
  );
}

export default PostDetailPanel;
