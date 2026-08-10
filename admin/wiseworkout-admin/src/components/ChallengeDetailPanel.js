import React from 'react';
import DetailDrawer from './ui/DetailDrawer';
import Badge from './ui/Badge';
import { formatDate } from '../utils/dateUtils';
import { resolveCategoryDisplay, formatGoal, computeChallengeStatus } from '../utils/challengeUtils';

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

function isChallengeDeletable(challenge) {
  const participantCount = Array.isArray(challenge?.participantUids) ? challenge.participantUids.length : 0;
  return challenge?.isGlobal === true && participantCount === 0;
}

function getUserDisplay(user) {
  if (!user) return null;

  const fullName = [user.firstName, user.lastName].filter(Boolean).join(' ').trim();
  const name =
    user.displayName ||
    user.name ||
    fullName ||
    user.username ||
    user.email ||
    null;

  const email = typeof user.email === 'string' ? user.email.trim() : '';

  return {
    name: name || 'Unknown user',
    email,
  };
}

function resolveCreator(challenge, usersById) {
  const creator = usersById?.get?.(challenge?.createdBy);
  const creatorDisplay = getUserDisplay(creator);

  if (challenge?.isGlobal === true) {
    return {
      sourceLabel: 'Global',
      creatorName: 'Admin',
      creatorEmail: creatorDisplay?.email || '',
      technicalId: challenge?.createdBy || '',
    };
  }

  return {
    sourceLabel: 'User-created',
    creatorName: creatorDisplay?.name || 'Unknown user',
    creatorEmail: creatorDisplay?.email || '',
    technicalId: challenge?.createdBy || '',
  };
}

function ChallengeDetailPanel({ challenge, categories, usersById, onClose, onDelete }) {
  if (!challenge) return null;

  const categoryDisplay = resolveCategoryDisplay(challenge.categoryId, categories);
  const status = computeChallengeStatus(challenge.startDate, challenge.endDate);
  const participantCount = Array.isArray(challenge.participantUids) ? challenge.participantUids.length : 0;
  const invitedCount = Array.isArray(challenge.invitedUids) ? challenge.invitedUids.length : 0;
  const creator = resolveCreator(challenge, usersById);
  const deletable = isChallengeDeletable(challenge);

  return (
    <DetailDrawer
      title="Challenge View"
      open={Boolean(challenge)}
      onClose={onClose}
      viewportLocked
      summary={(
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ fontSize: 18, fontWeight: 700, color: 'var(--ww-text)' }}>
            {challenge.name || challenge.title || 'Untitled challenge'}
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            <Badge tone={status === 'Active' ? 'success' : status === 'Upcoming' ? 'brand' : 'neutral'}>
              {status}
            </Badge>
            <Badge tone={challenge.isGlobal === true ? 'brand' : 'neutral'}>
              {creator.sourceLabel}
            </Badge>
          </div>
        </div>
      )}
      footer={
        deletable ? (
          <div className="wwa-cell-actions" style={{ width: '100%', marginTop: 0 }}>
            <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => onDelete?.(challenge)}>
              Delete
            </button>
          </div>
        ) : (
          <div style={{ fontSize: 12.5, color: '#6b7280' }}>
            {challenge.isGlobal === true
              ? 'Global challenges can only be deleted when they have no participants.'
              : 'User-created challenges are managed by their creator in the mobile app.'}
          </div>
        )
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
        <section>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 10 }}>Overview</div>
          <DetailRow
            label="Category"
            value={categoryDisplay.missing ? `${categoryDisplay.text} (category not found)` : categoryDisplay.text}
          />
          <DetailRow label="Metric" value={challenge.metricType || '—'} />
          <DetailRow label="Goal" value={formatGoal(challenge, categories)} />
          <DetailRow label="Unit" value={challenge.unit || '—'} />
        </section>

        <section>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 10 }}>Schedule</div>
          <DetailRow label="Start Date" value={formatDate(challenge.startDate)} />
          <DetailRow label="End Date" value={formatDate(challenge.endDate)} />
          <DetailRow label="Created Date" value={formatDate(challenge.createdAt)} />
        </section>

        <section>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 10 }}>Source</div>
          <DetailRow label="Source Type" value={creator.sourceLabel} />
          <DetailRow label="Creator" value={creator.creatorName} />
          <DetailRow label="Creator Email" value={creator.creatorEmail || undefined} />
          <DetailRow
            label="Creator UID"
            value={creator.technicalId ? <span style={monoStyle}>{creator.technicalId}</span> : undefined}
          />
        </section>

        <section>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 10 }}>Membership</div>
          <DetailRow label="Participants" value={participantCount} />
          <DetailRow label="Invited" value={invitedCount} />
        </section>

        <section>
          <div className="wwa-panel-subtitle" style={{ marginBottom: 10 }}>Technical</div>
          <DetailRow label="Challenge ID" value={<span style={monoStyle}>{challenge.id}</span>} />
          <DetailRow
            label="Category ID"
            value={challenge.categoryId ? <span style={monoStyle}>{challenge.categoryId}</span> : undefined}
          />
        </section>
      </div>
    </DetailDrawer>
  );
}

export default ChallengeDetailPanel;
