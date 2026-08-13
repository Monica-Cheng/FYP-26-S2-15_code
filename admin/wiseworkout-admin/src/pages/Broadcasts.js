import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import DataTable from '../components/ui/DataTable';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import DetailDrawer from '../components/ui/DetailDrawer';
import ModalDialog from '../components/ui/ModalDialog';
import SearchInput from '../components/ui/SearchInput';
import FilterBar from '../components/ui/FilterBar';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import useClientPagination from '../hooks/useClientPagination';
import { formatDate } from '../utils/dateUtils';
import { broadcastAudienceLabel, broadcastStatusLabel } from '../utils/broadcastUtils';

const MAX_MESSAGE_LENGTH = 500;
const SEND_CONFIRMATION = 'SEND TO ALL USERS';

function BroadcastsStyles() {
  return (
    <style>{`
      .wwbr-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbr-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwbr-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
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
      .wwbr-message-preview {
        max-height: 220px;
        overflow: auto;
        padding: 14px 16px;
        border-radius: 12px;
        border: 1px solid var(--ww-divider);
        background: color-mix(in srgb, var(--ww-elevated) 55%, white);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
      }
      .wwbr-detail-summary {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwbr-detail-summary__message {
        color: var(--ww-text);
        line-height: 1.55;
        white-space: pre-wrap;
      }
      .wwbr-detail-summary__meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
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
      .wwbr-modal-copy {
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
      .wwa-modal {
        position: fixed;
        inset: 0;
        z-index: 1200;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: rgba(15, 23, 42, 0.58);
        backdrop-filter: blur(2px);
      }
      .wwa-modal__panel {
        width: min(100%, 640px);
        max-height: calc(100vh - 48px);
        overflow: auto;
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: 20px;
        box-shadow: var(--ww-shadow-lg);
      }
      .wwa-modal__header,
      .wwa-modal__footer {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
        padding: 18px 20px;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwa-modal__footer {
        align-items: center;
        justify-content: flex-end;
        border-top: 1px solid var(--ww-divider);
        border-bottom: 0;
        flex-wrap: wrap;
      }
      .wwa-modal__header-main {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .wwa-modal__title {
        margin: 0;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwa-modal__description {
        margin: 0;
        font-size: var(--ww-type-body-size);
        color: var(--ww-text-sec);
        line-height: 1.55;
      }
      .wwa-modal__body {
        padding: 20px;
      }
      @media (max-width: 720px) {
        .wwa-modal {
          padding: 12px;
        }
      }
      @media (max-width: 1160px) {
        .wwbr-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
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

function Broadcasts() {
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const [composerError, setComposerError] = useState('');
  const [modalError, setModalError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [broadcasts, setBroadcasts] = useState([]);
  const [loadingHistory, setLoadingHistory] = useState(true);
  const [refreshingHistory, setRefreshingHistory] = useState(false);
  const [refreshError, setRefreshError] = useState('');
  const [recipientCount, setRecipientCount] = useState(0);
  const [search, setSearch] = useState('');
  const [selectedBroadcastId, setSelectedBroadcastId] = useState(null);
  const [sendModalOpen, setSendModalOpen] = useState(false);
  const [sendConfirmation, setSendConfirmation] = useState('');

  const fetchHistory = useCallback(async ({ background = false } = {}) => {
    if (background) {
      setRefreshingHistory(true);
      setRefreshError('');
    } else {
      setLoadingHistory(true);
      setLoadError('');
    }

    try {
      const adminListBroadcastDashboard = httpsCallable(functions, 'adminListBroadcastDashboard');
      const result = await adminListBroadcastDashboard();
      const data = result.data || {};

      setBroadcasts(Array.isArray(data.broadcasts) ? data.broadcasts : []);
      setRecipientCount(Number.isInteger(data.recipientCount) ? data.recipientCount : 0);
      if (background) {
        setRefreshError('');
      }
    } catch (err) {
      console.error('Failed to load broadcast dashboard:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      if (background) {
        setRefreshError(`Broadcast history refresh failed.${detail}`);
      } else {
        setLoadError(`Failed to load broadcast history.${detail}`);
      }
    } finally {
      if (background) {
        setRefreshingHistory(false);
      } else {
        setLoadingHistory(false);
      }
    }
  }, []);

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  const trimmedMessage = message.trim();
  const selectedBroadcast = broadcasts.find((broadcast) => broadcast.id === selectedBroadcastId) || null;

  const handleSendClick = () => {
    if (!trimmedMessage) {
      setComposerError('Broadcast message is required.');
      return;
    }
    setComposerError('');
    setSuccessMsg('');
    setModalError('');
    setSendConfirmation('');
    setSendModalOpen(true);
  };

  const handleCloseSendModal = () => {
    if (sending) return;
    setSendModalOpen(false);
    setSendConfirmation('');
    setModalError('');
  };

  const handleConfirmSend = async () => {
    setSending(true);
    setModalError('');

    try {
      const adminCreateBroadcast = httpsCallable(functions, 'adminCreateBroadcast');
      const result = await adminCreateBroadcast({
        message: trimmedMessage,
        confirmation: sendConfirmation,
      });

      const sentCount = result.data?.recipientCount ?? recipientCount;

      setMessage('');
      setComposerError('');
      setSendModalOpen(false);
      setSendConfirmation('');
      setRecipientCount(sentCount);
      setSuccessMsg(`Broadcast queued successfully for ${sentCount} users.`);

      void fetchHistory({ background: true });
    } catch (err) {
      console.error('Failed to send broadcast:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setModalError(`Failed to send broadcast. Please try again.${detail}`);
    } finally {
      setSending(false);
    }
  };

  const filtered = useMemo(() => {
    return broadcasts.filter((broadcast) => {
      const query = search.toLowerCase();
      if (!query) return true;

      return (
        (broadcast.message || '').toLowerCase().includes(query) ||
        (broadcast.id || '').toLowerCase().includes(query) ||
        (broadcast.createdByAdminUid || '').toLowerCase().includes(query) ||
        broadcastStatusLabel(broadcast.processed).toLowerCase().includes(query)
      );
    });
  }, [broadcasts, search]);

  const broadcastsPagination = useClientPagination(filtered, {
    resetKey: search,
  });

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
      key: 'recipients',
      header: 'Recipients',
      render: (broadcast) => broadcast.recipientCount ?? '—',
    },
    {
      key: 'createdAt',
      header: 'Created At',
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

        {composerError ? <div className="wwa-alert-error">{composerError}</div> : null}
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
            onChange={(event) => {
              setMessage(event.target.value);
              if (composerError) setComposerError('');
            }}
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

        <div className="wwa-cell-actions">
          <button
            type="button"
            className="wwa-btn wwa-btn-primary"
            onClick={handleSendClick}
            disabled={sending || loadingHistory || recipientCount <= 0 || !trimmedMessage}
          >
            Send Broadcast
          </button>
        </div>
      </div>

      <div className="wwbr-history-header">
        <div className="wwa-panel-title">Broadcast History</div>
        <div className="wwa-panel-subtitle">Recent broadcasts and their delivery status</div>
      </div>

      {loadError && broadcasts.length === 0 ? (
        <ErrorState
          title="Failed to load broadcast history"
          message={loadError}
          onRetry={fetchHistory}
        />
      ) : loadingHistory ? (
        <LoadingState rows={5} />
      ) : (
        <>
          <FilterBar
            search={
              <SearchInput
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                onClear={() => setSearch('')}
                placeholder="Search broadcasts…"
                label="Search broadcasts"
              />
            }
            count={`${filtered.length} of ${broadcasts.length} broadcasts`}
          />

          {loadError ? <div className="wwa-alert-error">{loadError}</div> : null}
          {refreshingHistory ? <div className="wwa-help-text">Refreshing broadcast history…</div> : null}
          {refreshError ? <div className="wwa-alert-error">{refreshError}</div> : null}

          <div className={`wwbr-layout ${selectedBroadcast ? 'has-detail' : ''}`}>
            <div>
              <DataTable
                className="wwbr-history-table"
                columns={columns}
                rows={broadcastsPagination.paginatedItems}
                getRowKey={(broadcast) => broadcast.id}
                selectedRowKey={selectedBroadcastId}
                onRowClick={(broadcast) => setSelectedBroadcastId(broadcast.id)}
                minWidth={860}
                pagination={{
                  currentPage: broadcastsPagination.currentPage,
                  pageSize: broadcastsPagination.pageSize,
                  totalItems: broadcastsPagination.totalItems,
                  totalPages: broadcastsPagination.totalPages,
                  pageSizeOptions: broadcastsPagination.pageSizeOptions,
                  onPageChange: broadcastsPagination.setCurrentPage,
                  onPageSizeChange: broadcastsPagination.setPageSize,
                }}
                emptyTitle="No broadcasts yet"
                emptyMessage={search ? 'Try a different search term.' : 'Sent broadcasts will appear here.'}
                emptyIcon={null}
                actionsLabel="View"
                renderRowActions={(broadcast) => (
                  <div className="wwa-cell-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                      onClick={(event) => {
                        event.stopPropagation();
                        setSelectedBroadcastId(broadcast.id);
                      }}
                    >
                      View
                    </button>
                  </div>
                )}
              />
            </div>

            {selectedBroadcast ? (
              <DetailDrawer
                title="Broadcast"
                open={Boolean(selectedBroadcast)}
                onClose={() => setSelectedBroadcastId(null)}
                summary={(
                  <div className="wwbr-detail-summary">
                    <div className="wwbr-detail-summary__message">{selectedBroadcast.message || '—'}</div>
                    <div className="wwbr-detail-summary__meta">
                      <Badge tone="brand">{broadcastAudienceLabel(selectedBroadcast.audience)}</Badge>
                      <Badge tone={selectedBroadcast.processed === true ? 'success' : 'warning'}>
                        {broadcastStatusLabel(selectedBroadcast.processed)}
                      </Badge>
                    </div>
                  </div>
                )}
              >
                <section className="wwa-detail-section">
                  <div className="wwa-detail-section__title">Details</div>
                  <DetailRow label="Broadcast ID" value={selectedBroadcast.id || '—'} />
                  <DetailRow label="Audience" value={broadcastAudienceLabel(selectedBroadcast.audience)} />
                  <DetailRow label="Recipients" value={selectedBroadcast.recipientCount ?? '—'} />
                  <DetailRow label="Created At" value={formatDate(selectedBroadcast.createdAt)} />
                  <DetailRow label="Status" value={broadcastStatusLabel(selectedBroadcast.processed)} />
                  <DetailRow label="Created By" value={selectedBroadcast.createdByAdminUid || undefined} />
                </section>

                <section className="wwa-detail-section">
                  <div className="wwa-detail-section__title">Message</div>
                  <div className="wwbr-message-preview">{selectedBroadcast.message || '—'}</div>
                </section>
              </DetailDrawer>
            ) : null}
          </div>
        </>
      )}

      <ModalDialog
        open={sendModalOpen}
        title="Send Broadcast"
        description="This will send the broadcast to all current WiseWorkout users."
        onClose={handleCloseSendModal}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={handleCloseSendModal} disabled={sending}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-primary"
              onClick={handleConfirmSend}
              disabled={sending || sendConfirmation !== SEND_CONFIRMATION}
            >
              {sending ? 'Sending...' : 'Send Broadcast'}
            </button>
          </>
        }
      >
        <div className="wwbr-modal-copy">
          This broadcast will be delivered to every current WiseWorkout account.
        </div>

        <FormSection title="Audience" columns={2}>
          <DetailRow label="Audience" value="All Users" />
          <DetailRow label="Recipients" value={recipientCount} />
        </FormSection>

        <FormSection title="Message Preview" columns={1}>
          <div className="wwbr-message-preview">{trimmedMessage || '—'}</div>
        </FormSection>

        <FormSection columns={1}>
          <FormField label="Confirmation" labelFor="broadcast-send-confirmation" required fullWidth>
            <input
              id="broadcast-send-confirmation"
              type="text"
              className="wwa-input"
              value={sendConfirmation}
              onChange={(event) => setSendConfirmation(event.target.value)}
              placeholder={SEND_CONFIRMATION}
            />
          </FormField>
        </FormSection>

        {modalError ? <div className="wwa-alert-error">{modalError}</div> : null}
      </ModalDialog>
    </div>
  );
}

export default Broadcasts;
