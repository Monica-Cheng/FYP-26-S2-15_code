import React, { useCallback, useEffect, useState } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import DataTable from '../components/ui/DataTable';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import { formatDate } from '../utils/dateUtils';
import { broadcastAudienceLabel, broadcastStatusLabel } from '../utils/broadcastUtils';

const MAX_MESSAGE_LENGTH = 500;

function BroadcastsStyles() {
  return (
    <style>{`
      .wwbr-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbr-composer {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbr-composer__header {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .wwbr-composer__title {
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-text);
      }
      .wwbr-composer__subtitle {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwbr-composer__field {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .wwbr-composer__textarea {
        min-height: 128px;
        resize: vertical;
        font-family: inherit;
      }
      .wwbr-composer__count {
        align-self: flex-end;
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwbr-audience {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwbr-audience__row {
        display: flex;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwbr-audience__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwbr-confirm {
        background: color-mix(in srgb, var(--ww-elevated) 55%, white);
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        padding: 14px 16px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwbr-confirm__label {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwbr-history-header {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .wwbr-message-cell {
        min-width: 0;
      }
      .wwbr-message-cell__text {
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
        line-height: 1.5;
      }
      .wwbr-history-table .wwa-table td {
        vertical-align: top;
      }
    `}</style>
  );
}

function Broadcasts() {
  const [message, setMessage] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [broadcasts, setBroadcasts] = useState([]);
  const [loadingHistory, setLoadingHistory] = useState(true);
  const [recipientCount, setRecipientCount] = useState(0);

  const fetchHistory = useCallback(async () => {
    setLoadingHistory(true);

    try {
      const adminListBroadcastDashboard = httpsCallable(functions, 'adminListBroadcastDashboard');
      const result = await adminListBroadcastDashboard();
      const data = result.data || {};

      setBroadcasts(Array.isArray(data.broadcasts) ? data.broadcasts : []);
      setRecipientCount(Number.isInteger(data.recipientCount) ? data.recipientCount : 0);
      setError('');
    } catch (err) {
      console.error('Failed to load broadcast dashboard:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setError(`Failed to load broadcast history.${detail}`);
    } finally {
      setLoadingHistory(false);
    }
  }, []);

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  const handleSendClick = () => {
    if (!message.trim()) return;
    setError('');
    setSuccessMsg('');
    setConfirming(true);
  };

  const handleConfirmSend = async () => {
    const confirmation = window.prompt(
      `This will send the notification to ${recipientCount} users.\n\n` +
      'Type SEND TO ALL USERS exactly to continue:'
    );

    if (confirmation !== 'SEND TO ALL USERS') {
      setConfirming(false);
      return;
    }

    setSending(true);
    setError('');

    try {
      const adminCreateBroadcast = httpsCallable(functions, 'adminCreateBroadcast');
      const result = await adminCreateBroadcast({
        message: message.trim(),
        confirmation,
      });

      const sentCount = result.data?.recipientCount ?? recipientCount;

      setMessage('');
      setConfirming(false);
      setSuccessMsg(`Broadcast queued successfully for ${sentCount} users.`);

      await fetchHistory();
    } catch (err) {
      console.error('Failed to send broadcast:', err);
      setConfirming(false);
      const detail = err?.code ? ` (${err.code})` : '';
      setError(`Failed to send broadcast. Please try again.${detail}`);
    } finally {
      setSending(false);
    }
  };

  const columns = [
    {
      key: 'message',
      header: 'Message',
      render: (broadcast) => (
        <div className="wwbr-message-cell">
          <div className="wwbr-message-cell__text">{broadcast.message || '—'}</div>
        </div>
      ),
    },
    {
      key: 'audience',
      header: 'Audience',
      render: (broadcast) => broadcastAudienceLabel(broadcast.audience),
    },
    {
      key: 'sent',
      header: 'Sent',
      render: (broadcast) => formatDate(broadcast.createdAt),
    },
    {
      key: 'status',
      header: 'Status',
      render: (broadcast) => (
        <Badge tone={broadcast.processed === true ? 'success' : 'warning'}>
          {broadcastStatusLabel(broadcast.processed)}
        </Badge>
      ),
    },
  ];

  return (
    <div className="wwbr-page">
      <AdminStyles />
      <BroadcastsStyles />

      <PageHeader
        title="Broadcasts"
        description="Send notifications and review broadcast history"
        count={loadingHistory ? undefined : `${broadcasts.length} broadcasts`}
      />

      <div className="wwa-panel wwbr-composer">
        <div className="wwbr-composer__header">
          <div className="wwbr-composer__title">New Broadcast</div>
          <div className="wwbr-composer__subtitle">Send a notification to WiseWorkout users</div>
        </div>

        {error ? <div className="wwa-alert-error">{error}</div> : null}
        {successMsg ? (
          <div className="wwa-status-pill">
            <span className="wwa-status-dot" />
            {successMsg}
          </div>
        ) : null}

        <div className="wwbr-composer__field">
          <label className="wwa-field-label" htmlFor="broadcast-message">Notification Message</label>
          <textarea
            id="broadcast-message"
            className="wwa-input wwbr-composer__textarea"
            rows={4}
            required
            maxLength={MAX_MESSAGE_LENGTH}
            value={message}
            onChange={(event) => setMessage(event.target.value)}
            placeholder="Type the message to send to users…"
            disabled={sending}
          />
          <div className="wwbr-composer__count">
            {message.length} / {MAX_MESSAGE_LENGTH}
          </div>
        </div>

        <div className="wwbr-audience">
          <label className="wwa-field-label">Audience</label>
          <div className="wwbr-audience__row">
            <Badge tone="brand">All Users</Badge>
            <span className="wwbr-audience__meta">{recipientCount} recipients</span>
          </div>
          <div className="wwbr-audience__meta">
            Delivered to all current WiseWorkout accounts.
          </div>
        </div>

        {!confirming ? (
          <div className="wwa-cell-actions">
            <button
              type="button"
              className="wwa-btn wwa-btn-primary"
              onClick={handleSendClick}
              disabled={sending || loadingHistory || recipientCount <= 0 || !message.trim()}
            >
              Send Broadcast
            </button>
          </div>
        ) : (
          <div className="wwbr-confirm">
            <span className="wwbr-confirm__label">Send this notification to all WiseWorkout users?</span>
            <div className="wwa-cell-actions">
              <button
                type="button"
                className="wwa-btn wwa-btn-secondary"
                onClick={() => setConfirming(false)}
                disabled={sending}
              >
                Cancel
              </button>
              <button
                type="button"
                className="wwa-btn wwa-btn-primary"
                onClick={handleConfirmSend}
                disabled={sending}
              >
                {sending ? 'Sending...' : 'Send'}
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="wwbr-history-header">
        <div className="wwa-panel-title">Broadcast History</div>
        <div className="wwa-panel-subtitle">Recent broadcasts and their delivery status</div>
      </div>

      {loadingHistory ? (
        <LoadingState rows={5} />
      ) : error && broadcasts.length === 0 ? (
        <ErrorState
          title="Failed to load broadcast history"
          message={error}
          onRetry={fetchHistory}
        />
      ) : (
        <DataTable
          className="wwbr-history-table"
          columns={columns}
          rows={broadcasts}
          getRowKey={(broadcast) => broadcast.id}
          minWidth={720}
          emptyTitle="No broadcasts yet"
          emptyMessage="Sent broadcasts will appear here."
          emptyIcon={null}
        />
      )}
    </div>
  );
}

export default Broadcasts;
