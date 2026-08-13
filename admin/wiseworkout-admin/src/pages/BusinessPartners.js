import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { FileQuestion, FileText } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import DetailDrawer from '../components/ui/DetailDrawer';
import FilterBar from '../components/ui/FilterBar';
import SearchInput from '../components/ui/SearchInput';
import SelectField from '../components/ui/SelectField';
import DataTable from '../components/ui/DataTable';
import FormSection from '../components/ui/FormSection';
import FormField from '../components/ui/FormField';
import LoadingState from '../components/ui/LoadingState';
import ErrorState from '../components/ui/ErrorState';
import ModalDialog from '../components/ui/ModalDialog';
import useClientPagination from '../hooks/useClientPagination';
import { formatDate } from '../utils/dateUtils';
import { getCallableErrorMessage } from '../utils/planUtils';

const APPROVE_CONFIRMATION = 'APPROVE PARTNER';
const REVOKE_CONFIRMATION = 'REVOKE PARTNER';

const getPartnerStatus = (partner) => (partner?.isApproved === true ? 'approved' : 'pending');

const statusLabel = (status) => (status === 'approved' ? 'Approved' : 'Pending');
const statusTone = (status) => (status === 'approved' ? 'success' : 'warning');

const getCredentialUrls = (partner) =>
  (Array.isArray(partner?.credentialUrls) ? partner.credentialUrls : []).filter(
    (value) => typeof value === 'string' && value.trim()
  );

const getCredentialSummary = (partner) => {
  const count = getCredentialUrls(partner).length;
  if (count === 0) return 'None';
  return `${count} document${count === 1 ? '' : 's'}`;
};

const getProfessionalType = (partner) => {
  const value = typeof partner?.type === 'string' ? partner.type.trim() : '';
  return value || '—';
};

function decodeCredentialPath(url) {
  if (typeof url !== 'string' || !url.trim()) return '';

  try {
    const parsed = new URL(url);
    return decodeURIComponent(parsed.pathname || '');
  } catch (error) {
    return decodeURIComponent(url);
  }
}

function inferCredentialType(url) {
  const path = decodeCredentialPath(url).toLowerCase();

  if (/\.(jpg|jpeg|png|webp)(?:$|[?#])/.test(path)) {
    return 'image';
  }

  if (/\.(pdf)(?:$|[?#])/.test(path)) {
    return 'pdf';
  }

  return 'document';
}

function BusinessPartnersStyles() {
  return (
    <style>{`
      .wwbp-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbp-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwbp-layout.has-detail {
        grid-template-columns: minmax(0, 1fr) minmax(440px, var(--ww-drawer-width-wide));
        align-items: start;
      }
      .wwbp-filter-grid {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
      }
      .wwbp-filter-grid > * {
        min-width: 180px;
        flex: 0 1 220px;
      }
      .wwbp-applicant {
        min-width: 0;
      }
      .wwbp-applicant__name {
        font-size: var(--ww-type-body-size);
        font-weight: 700;
        color: var(--ww-text);
        line-height: 1.35;
      }
      .wwbp-applicant__meta,
      .wwbp-cell-muted {
        margin-top: 4px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.45;
      }
      .wwbp-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwbp-drawer-summary {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwbp-drawer-summary__title {
        font-size: var(--ww-type-page-title-size);
        font-weight: var(--ww-type-page-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.15;
      }
      .wwbp-drawer-summary__meta {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 8px;
      }
      .wwbp-detail-row {
        display: grid;
        grid-template-columns: minmax(120px, 160px) minmax(0, 1fr);
        gap: 14px;
        align-items: start;
        padding: 10px 0;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwbp-detail-row:last-child {
        border-bottom: 0;
      }
      .wwbp-detail-label {
        font-size: var(--ww-type-secondary-size);
        font-weight: 700;
        color: var(--ww-text-sec);
      }
      .wwbp-detail-value {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
        word-break: break-word;
      }
      .wwbp-credentials {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 14px;
      }
      .wwbp-credential-card {
        display: flex;
        flex-direction: column;
        gap: 12px;
        min-height: 220px;
        padding: 14px;
        border: 1px solid var(--ww-divider);
        border-radius: 16px;
        background: var(--ww-card);
        box-shadow: var(--ww-shadow-sm);
      }
      .wwbp-credential-card__preview {
        position: relative;
        min-height: 132px;
        border-radius: 12px;
        overflow: hidden;
        border: 1px solid var(--ww-divider);
        background: color-mix(in srgb, var(--ww-bg) 82%, white);
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .wwbp-credential-card__preview button {
        width: 100%;
        height: 100%;
        padding: 0;
        border: 0;
        background: transparent;
        cursor: pointer;
      }
      .wwbp-credential-card__image {
        width: 100%;
        height: 132px;
        object-fit: cover;
        display: block;
      }
      .wwbp-credential-card__icon {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 8px;
        color: var(--ww-text-sec);
        text-align: center;
        padding: 18px;
      }
      .wwbp-credential-card__title {
        font-size: var(--ww-type-body-size);
        font-weight: 700;
        color: var(--ww-text);
      }
      .wwbp-credential-card__meta {
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
      }
      .wwbp-credential-card__actions {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: auto;
      }
      .wwbp-no-credentials {
        padding: 16px;
        border: 1px dashed var(--ww-divider);
        border-radius: 16px;
        background: color-mix(in srgb, var(--ww-bg) 70%, white);
        font-size: var(--ww-type-body-size);
        color: var(--ww-text-sec);
      }
      .wwbp-alert-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwbp-dialog-copy {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
      }
      .wwbp-dialog-note {
        margin-top: 10px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
      .wwbp-dialog-error {
        margin-top: 12px;
        padding: 12px 14px;
        border: 1px solid color-mix(in srgb, var(--ww-danger) 22%, white);
        border-radius: 12px;
        background: color-mix(in srgb, var(--ww-danger) 8%, white);
        color: var(--ww-danger);
        font-size: var(--ww-type-secondary-size);
        line-height: 1.5;
      }
      .wwbp-image-viewer {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwbp-image-viewer__frame {
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: min(70vh, 720px);
        max-height: 70vh;
        padding: 12px;
        border-radius: 16px;
        background: #0f172a;
        overflow: auto;
      }
      .wwbp-image-viewer__image {
        max-width: 100%;
        max-height: calc(70vh - 24px);
        object-fit: contain;
        border-radius: 10px;
        background: white;
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
        width: min(100%, 560px);
        max-height: calc(100vh - 48px);
        overflow: auto;
        background: var(--ww-card);
        border: 1px solid var(--ww-divider);
        border-radius: 20px;
        box-shadow: var(--ww-shadow-lg);
      }
      .wwa-modal__panel-lg {
        width: min(100%, 760px);
      }
      .wwa-modal__panel-xl {
        width: min(100%, 1040px);
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
      @media (max-width: 1240px) {
        .wwbp-layout.has-detail {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @media (max-width: 720px) {
        .wwbp-filter-grid > * {
          min-width: 100%;
          flex-basis: 100%;
        }
        .wwbp-detail-row {
          grid-template-columns: minmax(0, 1fr);
          gap: 6px;
        }
        .wwa-modal {
          padding: 12px;
        }
      }
    `}</style>
  );
}

function DetailRow({ label, value, multiline = false }) {
  if (value === undefined || value === null || value === '') {
    return null;
  }

  return (
    <div className="wwbp-detail-row">
      <div className="wwbp-detail-label">{label}</div>
      <div className="wwbp-detail-value" style={multiline ? undefined : { whiteSpace: 'normal' }}>
        {value}
      </div>
    </div>
  );
}

function CredentialCard({ url, index, onViewImage }) {
  const [imageFailed, setImageFailed] = useState(false);
  const detectedType = inferCredentialType(url);
  const type = detectedType === 'image' && imageFailed ? 'document' : detectedType;
  const label = `Credential ${index + 1}`;

  return (
    <article className="wwbp-credential-card">
      <div className="wwbp-credential-card__preview">
        {type === 'image' ? (
          <button type="button" onClick={() => onViewImage(url, label)} aria-label={`View ${label}`}>
            <img
              src={url}
              alt={label}
              className="wwbp-credential-card__image"
              onError={() => setImageFailed(true)}
            />
          </button>
        ) : (
          <div className="wwbp-credential-card__icon">
            {type === 'pdf' ? <FileText aria-hidden="true" size={32} strokeWidth={1.8} /> : <FileQuestion aria-hidden="true" size={32} strokeWidth={1.8} />}
            <span>{type === 'pdf' ? 'PDF document' : 'Document'}</span>
          </div>
        )}
      </div>
      <div>
        <div className="wwbp-credential-card__title">{label}</div>
        <div className="wwbp-credential-card__meta">
          {type === 'image' ? 'Image credential' : type === 'pdf' ? 'PDF credential' : 'Open document in a new tab'}
        </div>
      </div>
      <div className="wwbp-credential-card__actions">
        {type === 'image' ? (
          <button type="button" className="wwa-btn wwa-btn-secondary wwa-btn-sm" onClick={() => onViewImage(url, label)}>
            View full size
          </button>
        ) : null}
        <a
          className="wwa-btn wwa-btn-ghost wwa-btn-sm"
          href={url}
          target="_blank"
          rel="noopener noreferrer"
        >
          {type === 'pdf' ? 'Open document' : 'Open original'}
        </a>
      </div>
    </article>
  );
}

function BusinessPartners() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [actionError, setActionError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [credentialsFilter, setCredentialsFilter] = useState('all');
  const [selectedPartnerId, setSelectedPartnerId] = useState(null);
  const [processingUid, setProcessingUid] = useState(null);
  const [approvalPartnerId, setApprovalPartnerId] = useState(null);
  const [approveConfirmation, setApproveConfirmation] = useState('');
  const [revokePartnerId, setRevokePartnerId] = useState(null);
  const [revokeConfirmation, setRevokeConfirmation] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [viewerCredential, setViewerCredential] = useState(null);

  const fetchPartners = useCallback(async ({ silent = false } = {}) => {
    if (!silent) {
      setLoading(true);
    }
    setLoadError('');

    try {
      const adminListBusinessPartners = httpsCallable(functions, 'adminListBusinessPartners');
      const result = await adminListBusinessPartners();
      const loadedPartners = Array.isArray(result.data?.partners) ? result.data.partners : [];

      setPartners(loadedPartners);
    } catch (err) {
      console.error('Failed to load business partners:', err);
      setLoadError(getCallableErrorMessage(err, 'Failed to load business partners.'));
    } finally {
      if (!silent) {
        setLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    fetchPartners();
  }, [fetchPartners]);

  const selectedPartner = useMemo(
    () => partners.find((partner) => partner.id === selectedPartnerId) || null,
    [partners, selectedPartnerId]
  );

  const approvalPartner = useMemo(
    () => partners.find((partner) => partner.id === approvalPartnerId) || null,
    [partners, approvalPartnerId]
  );

  const revokePartner = useMemo(
    () => partners.find((partner) => partner.id === revokePartnerId) || null,
    [partners, revokePartnerId]
  );

  const typeOptions = useMemo(
    () =>
      Array.from(
        new Set(
          partners
            .map((partner) => (typeof partner.type === 'string' ? partner.type.trim() : ''))
            .filter(Boolean)
        )
      ).sort((a, b) => a.localeCompare(b)),
    [partners]
  );

  const filteredPartners = useMemo(() => {
    const query = search.trim().toLowerCase();

    return partners.filter((partner) => {
      const status = getPartnerStatus(partner);
      const hasCredentials = getCredentialUrls(partner).length > 0;
      const partnerType = typeof partner.type === 'string' ? partner.type.trim() : '';

      if (statusFilter !== 'all' && status !== statusFilter) {
        return false;
      }

      if (typeFilter !== 'all' && partnerType !== typeFilter) {
        return false;
      }

      if (credentialsFilter === 'with' && !hasCredentials) {
        return false;
      }

      if (credentialsFilter === 'without' && hasCredentials) {
        return false;
      }

      if (!query) {
        return true;
      }

      return [partner.name, partner.email, partner.type]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(query));
    });
  }, [credentialsFilter, partners, search, statusFilter, typeFilter]);

  const hasActiveFilters = Boolean(search || statusFilter !== 'all' || typeFilter !== 'all' || credentialsFilter !== 'all');

  const partnersPagination = useClientPagination(filteredPartners, {
    resetKey: [search, statusFilter, typeFilter, credentialsFilter].join('|'),
  });

  const resetFilters = () => {
    setSearch('');
    setStatusFilter('all');
    setTypeFilter('all');
    setCredentialsFilter('all');
  };

  const openApproveDialog = (partner) => {
    setActionError('');
    setApprovalPartnerId(partner.id);
    setApproveConfirmation('');
  };

  const closeApproveDialog = () => {
    setApprovalPartnerId(null);
    setApproveConfirmation('');
    setActionError('');
  };

  const openRevokeDialog = (partner) => {
    setActionError('');
    setRevokePartnerId(partner.id);
    setRevokeConfirmation('');
    setRevokeReason('');
  };

  const closeRevokeDialog = () => {
    setRevokePartnerId(null);
    setRevokeConfirmation('');
    setRevokeReason('');
    setActionError('');
  };

  const handleApprove = async () => {
    if (!approvalPartner) return;

    setProcessingUid(approvalPartner.id);
    setActionError('');
    setSuccessMsg('');

    try {
      const adminApproveBusinessPartner = httpsCallable(functions, 'adminApproveBusinessPartner');
      await adminApproveBusinessPartner({
        partnerUid: approvalPartner.id,
        confirmation: APPROVE_CONFIRMATION,
      });

      await fetchPartners({ silent: true });
      setSuccessMsg(`${approvalPartner.name || 'Business partner'} approved successfully.`);
      closeApproveDialog();
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to approve business partner:', err);
      setActionError(getCallableErrorMessage(err, 'Failed to approve business partner. Please try again.'));
    } finally {
      setProcessingUid(null);
    }
  };

  const handleRevoke = async () => {
    if (!revokePartner) return;

    setProcessingUid(revokePartner.id);
    setActionError('');
    setSuccessMsg('');

    try {
      const adminRevokeBusinessPartner = httpsCallable(functions, 'adminRevokeBusinessPartner');
      await adminRevokeBusinessPartner({
        partnerUid: revokePartner.id,
        confirmation: REVOKE_CONFIRMATION,
        reason: revokeReason.trim(),
      });

      await fetchPartners({ silent: true });
      setSuccessMsg(`${revokePartner.name || 'Business partner'} approval revoked successfully.`);
      closeRevokeDialog();
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to revoke business partner:', err);
      setActionError(getCallableErrorMessage(err, 'Failed to revoke professional access. Please try again.'));
    } finally {
      setProcessingUid(null);
    }
  };

  const columns = [
    {
      key: 'applicant',
      header: 'Applicant',
      render: (partner) => (
        <div className="wwbp-applicant">
          <div className="wwbp-applicant__name">{partner.name || 'Unnamed applicant'}</div>
          <div className="wwbp-applicant__meta">{partner.email || 'No email provided'}</div>
        </div>
      ),
    },
    {
      key: 'type',
      header: 'Professional Type',
      render: (partner) => getProfessionalType(partner),
    },
    {
      key: 'submitted',
      header: 'Submitted',
      render: (partner) => formatDate(partner.createdAt),
    },
    {
      key: 'credentials',
      header: 'Credentials',
      render: (partner) => getCredentialSummary(partner),
    },
    {
      key: 'status',
      header: 'Status',
      render: (partner) => <Badge tone={statusTone(getPartnerStatus(partner))}>{statusLabel(getPartnerStatus(partner))}</Badge>,
    },
  ];

  const renderCredentialSection = (partner) => {
    const urls = getCredentialUrls(partner);

    if (urls.length === 0) {
      return <div className="wwbp-no-credentials">No credential documents submitted.</div>;
    }

    return (
      <div className="wwbp-credentials">
        {urls.map((url, index) => (
          <CredentialCard key={`${partner.id}-credential-${index}`} url={url} index={index} onViewImage={(imageUrl, label) => setViewerCredential({ url: imageUrl, label })} />
        ))}
      </div>
    );
  };

  return (
    <div className="wwbp-page">
      <AdminStyles />
      <BusinessPartnersStyles />

      <PageHeader
        title="Business Partners"
        subtitle="Review professional applications and credentials."
        meta={loading ? 'Loading applications…' : `${partners.length} applications`}
      />

      <div className="wwbp-alert-stack">
        {successMsg ? (
          <div>
            <span className="wwa-status-pill">
              <span className="wwa-status-dot" />
              {successMsg}
            </span>
          </div>
        ) : null}
        {actionError ? (
          <div className="wwa-alert-error" role="alert">
            {actionError}
          </div>
        ) : null}
      </div>

      {loadError && !loading ? (
        <ErrorState
          title="Could not load business partners"
          message={loadError}
          onRetry={() => fetchPartners()}
        />
      ) : null}

      <div className={`wwbp-layout ${selectedPartner ? 'has-detail' : ''}`.trim()}>
        <div>
          <FilterBar
            search={
              <SearchInput
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search applicants..."
                label="Search applicants"
                onClear={() => setSearch('')}
              />
            }
            filters={
              <div className="wwbp-filter-grid">
                <SelectField
                  aria-label="Filter by status"
                  value={statusFilter}
                  onChange={(event) => setStatusFilter(event.target.value)}
                  options={[
                    { value: 'all', label: 'Status: All' },
                    { value: 'pending', label: 'Status: Pending' },
                    { value: 'approved', label: 'Status: Approved' },
                  ]}
                />
                <SelectField
                  aria-label="Filter by professional type"
                  value={typeFilter}
                  onChange={(event) => setTypeFilter(event.target.value)}
                  options={[
                    { value: 'all', label: 'Type: All' },
                    ...typeOptions.map((type) => ({ value: type, label: `Type: ${type}` })),
                  ]}
                />
                <SelectField
                  aria-label="Filter by credentials"
                  value={credentialsFilter}
                  onChange={(event) => setCredentialsFilter(event.target.value)}
                  options={[
                    { value: 'all', label: 'Credentials: All' },
                    { value: 'with', label: 'Credentials: Has credentials' },
                    { value: 'without', label: 'Credentials: No credentials' },
                  ]}
                />
              </div>
            }
            onReset={hasActiveFilters ? resetFilters : undefined}
            resetDisabled={!hasActiveFilters}
            count={loading ? 'Loading…' : `${filteredPartners.length} shown`}
          />

          {loading ? (
            <LoadingState rows={6} />
          ) : (
            <DataTable
              columns={columns}
              rows={partnersPagination.paginatedItems}
              getRowKey={(partner) => partner.id}
              selectedRowKey={selectedPartnerId}
              onRowClick={(partner) => {
                setSelectedPartnerId(partner.id);
                setActionError('');
              }}
              pagination={{
                currentPage: partnersPagination.currentPage,
                pageSize: partnersPagination.pageSize,
                totalItems: partnersPagination.totalItems,
                totalPages: partnersPagination.totalPages,
                pageSizeOptions: partnersPagination.pageSizeOptions,
                onPageChange: partnersPagination.setCurrentPage,
                onPageSizeChange: partnersPagination.setPageSize,
              }}
              renderRowActions={(partner) => {
                const status = getPartnerStatus(partner);
                const processing = processingUid === partner.id;

                return (
                  <div className="wwbp-actions">
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-secondary wwa-btn-sm"
                      onClick={() => {
                        setSelectedPartnerId(partner.id);
                        setActionError('');
                      }}
                    >
                      View
                    </button>
                    {status === 'pending' ? (
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-success wwa-btn-sm"
                        onClick={() => openApproveDialog(partner)}
                        disabled={processing}
                      >
                        {processing ? 'Approving…' : 'Approve'}
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-danger wwa-btn-sm"
                        onClick={() => openRevokeDialog(partner)}
                        disabled={processing}
                      >
                        {processing ? 'Revoking…' : 'Revoke'}
                      </button>
                    )}
                  </div>
                );
              }}
              minWidth={860}
              emptyTitle="No business partners found"
              emptyMessage={
                partners.length === 0
                  ? 'No professional applications have been submitted yet.'
                  : 'Try adjusting the search or filters.'
              }
              emptyIcon={null}
            />
          )}
        </div>

        {selectedPartner ? (
          <DetailDrawer
            open
            width="wide"
            title="Partner Details"
            onClose={() => setSelectedPartnerId(null)}
            summary={
              <div className="wwbp-drawer-summary">
                <div className="wwbp-drawer-summary__title">{selectedPartner.name || 'Unnamed applicant'}</div>
                <div className="wwbp-drawer-summary__meta">
                  <Badge tone="brand">{getProfessionalType(selectedPartner)}</Badge>
                  <Badge tone={statusTone(getPartnerStatus(selectedPartner))}>{statusLabel(getPartnerStatus(selectedPartner))}</Badge>
                </div>
              </div>
            }
            footer={
              getPartnerStatus(selectedPartner) === 'pending' ? (
                <button
                  type="button"
                  className="wwa-btn wwa-btn-success"
                  onClick={() => openApproveDialog(selectedPartner)}
                  disabled={processingUid === selectedPartner.id}
                >
                  {processingUid === selectedPartner.id ? 'Approving…' : 'Approve'}
                </button>
              ) : (
                <button
                  type="button"
                  className="wwa-btn wwa-btn-danger"
                  onClick={() => openRevokeDialog(selectedPartner)}
                  disabled={processingUid === selectedPartner.id}
                >
                  {processingUid === selectedPartner.id ? 'Revoking…' : 'Revoke'}
                </button>
              )
            }
          >
            <FormSection title="Application Details" columns={1}>
              <DetailRow label="Email" value={selectedPartner.email || '—'} />
              <DetailRow label="Experience" value={selectedPartner.experience || '—'} multiline />
              <DetailRow label="Bio" value={selectedPartner.bio || '—'} multiline />
              <DetailRow label="Submitted" value={formatDate(selectedPartner.createdAt)} />
            </FormSection>

            <FormSection title="Credential Documents" description="Inspect submitted certificates and supporting documents." columns={1}>
              {renderCredentialSection(selectedPartner)}
            </FormSection>

            <FormSection title="Review History / Status" columns={1}>
              <DetailRow label="Submitted" value={formatDate(selectedPartner.createdAt)} />
              <DetailRow label="Approved At" value={selectedPartner.approvedAt ? formatDate(selectedPartner.approvedAt) : undefined} />
              <DetailRow label="Approved By" value={selectedPartner.approvedByAdminUid || undefined} />
              <DetailRow label="Revoked At" value={selectedPartner.revokedAt ? formatDate(selectedPartner.revokedAt) : undefined} />
              <DetailRow label="Revoked By" value={selectedPartner.revokedByAdminUid || undefined} />
              <DetailRow label="Revocation Reason" value={selectedPartner.revocationReason || undefined} multiline />
            </FormSection>
          </DetailDrawer>
        ) : null}
      </div>

      <ModalDialog
        open={Boolean(approvalPartner)}
        title={approvalPartner ? `Approve ${approvalPartner.name || 'this applicant'}?` : 'Approve professional'}
        description="This will verify the professional, make their profile visible to users, and apply the existing backend side effects."
        onClose={processingUid ? undefined : closeApproveDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeApproveDialog} disabled={processingUid === approvalPartnerId}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-success"
              onClick={handleApprove}
              disabled={processingUid === approvalPartnerId || approveConfirmation.trim() !== APPROVE_CONFIRMATION}
            >
              {processingUid === approvalPartnerId ? 'Approving…' : 'Approve'}
            </button>
          </>
        }
      >
        <div className="wwbp-dialog-copy">
          Type <strong>{APPROVE_CONFIRMATION}</strong> to confirm this approval.
        </div>
        <FormSection columns={1}>
          <FormField label="Confirmation" labelFor="bp-approve-confirmation" required fullWidth>
            <input
              id="bp-approve-confirmation"
              type="text"
              className="wwa-input"
              value={approveConfirmation}
              onChange={(event) => setApproveConfirmation(event.target.value)}
              placeholder={APPROVE_CONFIRMATION}
            />
          </FormField>
        </FormSection>
        {actionError ? <div className="wwbp-dialog-error">{actionError}</div> : null}
      </ModalDialog>

      <ModalDialog
        open={Boolean(revokePartner)}
        title="Revoke Professional Access"
        description="This will make the professional not visible to users and the backend will remove their current premium entitlement. Revocation may be blocked if they still have active clients or pending requests."
        onClose={processingUid ? undefined : closeRevokeDialog}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={closeRevokeDialog} disabled={processingUid === revokePartnerId}>
              Cancel
            </button>
            <button
              type="button"
              className="wwa-btn wwa-btn-danger"
              onClick={handleRevoke}
              disabled={
                processingUid === revokePartnerId ||
                revokeConfirmation.trim() !== REVOKE_CONFIRMATION ||
                !revokeReason.trim()
              }
            >
              {processingUid === revokePartnerId ? 'Revoking…' : 'Revoke'}
            </button>
          </>
        }
      >
        <FormSection columns={1}>
          <FormField label="Reason" labelFor="bp-revoke-reason" required fullWidth>
            <textarea
              id="bp-revoke-reason"
              className="wwa-input"
              rows={5}
              value={revokeReason}
              onChange={(event) => setRevokeReason(event.target.value)}
              placeholder="Explain why this professional access is being revoked."
            />
          </FormField>
          <FormField label="Confirmation" labelFor="bp-revoke-confirmation" required fullWidth>
            <input
              id="bp-revoke-confirmation"
              type="text"
              className="wwa-input"
              value={revokeConfirmation}
              onChange={(event) => setRevokeConfirmation(event.target.value)}
              placeholder={REVOKE_CONFIRMATION}
            />
          </FormField>
        </FormSection>
        {actionError ? <div className="wwbp-dialog-error">{actionError}</div> : null}
      </ModalDialog>

      <ModalDialog
        open={Boolean(viewerCredential)}
        title={viewerCredential?.label || 'Credential image'}
        size="xl"
        onClose={() => setViewerCredential(null)}
        footer={
          <>
            <button type="button" className="wwa-btn wwa-btn-ghost" onClick={() => setViewerCredential(null)}>
              Close
            </button>
            {viewerCredential?.url ? (
              <a className="wwa-btn wwa-btn-secondary" href={viewerCredential.url} target="_blank" rel="noopener noreferrer">
                Open original
              </a>
            ) : null}
          </>
        }
      >
        <div className="wwbp-image-viewer">
          <div className="wwbp-image-viewer__frame">
            {viewerCredential?.url ? (
              <img src={viewerCredential.url} alt={viewerCredential.label || 'Credential'} className="wwbp-image-viewer__image" />
            ) : null}
          </div>
        </div>
      </ModalDialog>
    </div>
  );
}

export default BusinessPartners;
