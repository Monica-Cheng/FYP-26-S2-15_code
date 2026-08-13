import React, { useMemo } from 'react';

function buildPageItems(currentPage, totalPages) {
  if (totalPages <= 9) {
    return Array.from({ length: totalPages }, (_, index) => index + 1);
  }

  if (currentPage <= 5) {
    return [1, 2, 3, 4, 5, 'ellipsis-right', totalPages];
  }

  if (currentPage >= totalPages - 4) {
    return [1, 'ellipsis-left', totalPages - 4, totalPages - 3, totalPages - 2, totalPages - 1, totalPages];
  }

  return [
    1,
    'ellipsis-left',
    currentPage - 2,
    currentPage - 1,
    currentPage,
    currentPage + 1,
    currentPage + 2,
    'ellipsis-right',
    totalPages,
  ];
}

function TablePagination({
  currentPage = 1,
  pageSize = 20,
  totalItems = 0,
  totalPages = 1,
  pageSizeOptions = [10, 20, 50],
  onPageChange,
  onPageSizeChange,
}) {
  const startItem = totalItems === 0 ? 0 : (currentPage - 1) * pageSize + 1;
  const endItem = totalItems === 0 ? 0 : Math.min(currentPage * pageSize, totalItems);
  const pageItems = useMemo(
    () => buildPageItems(currentPage, totalPages),
    [currentPage, totalPages]
  );

  return (
    <div className="wwa-table-pagination">
      <div className="wwa-table-pagination__summary">
        {totalItems === 0 ? 'Showing 0 of 0' : `Showing ${startItem}\u2013${endItem} of ${totalItems}`}
      </div>

      <div className="wwa-table-pagination__controls">
        <div className="wwa-table-pagination__pages" aria-label="Pagination">
          <button
            type="button"
            className="wwa-btn wwa-btn-sm wwa-btn-secondary"
            onClick={() => onPageChange?.(currentPage - 1)}
            disabled={currentPage <= 1}
          >
            Previous
          </button>

          {pageItems.map((item, index) =>
            typeof item === 'number' ? (
              <button
                key={item}
                type="button"
                className={`wwa-btn wwa-btn-sm ${item === currentPage ? 'wwa-btn-primary' : 'wwa-btn-secondary'}`}
                onClick={() => onPageChange?.(item)}
                aria-current={item === currentPage ? 'page' : undefined}
              >
                {item}
              </button>
            ) : (
              <span key={`${item}-${index}`} className="wwa-table-pagination__ellipsis" aria-hidden="true">
                ...
              </span>
            )
          )}

          <button
            type="button"
            className="wwa-btn wwa-btn-sm wwa-btn-secondary"
            onClick={() => onPageChange?.(currentPage + 1)}
            disabled={currentPage >= totalPages}
          >
            Next
          </button>
        </div>

        <label className="wwa-table-pagination__page-size">
          <span>Rows per page:</span>
          <select
            className="wwa-select"
            value={String(pageSize)}
            onChange={(event) => onPageSizeChange?.(Number(event.target.value))}
          >
            {pageSizeOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
      </div>
    </div>
  );
}

export default TablePagination;
