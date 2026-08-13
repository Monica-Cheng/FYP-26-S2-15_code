import React from 'react';
import EmptyState from './EmptyState';
import TablePagination from './TablePagination';

function DataTable({
  columns = [],
  rows = [],
  getRowKey,
  loading = false,
  loadingRows = 6,
  selectedRowKey,
  onRowClick,
  renderRowActions,
  actionsLabel = 'Actions',
  dense = false,
  minWidth = 640,
  emptyTitle = 'No results found',
  emptyMessage = 'Try adjusting your filters or search.',
  emptyIcon,
  className = '',
  pagination,
}) {
  const hasActions = typeof renderRowActions === 'function';
  const skeletonCount = Math.max(1, loadingRows);

  return (
    <div className={`wwa-data-table ${dense ? 'wwa-data-table-dense' : ''} ${className}`.trim()}>
      <div className="wwa-data-table__scroll">
        <table className="wwa-table wwa-data-table__table" style={{ minWidth }}>
          <thead>
            <tr>
              {columns.map((column) => (
                <th
                  key={column.key}
                  className={[
                    column.align === 'right' || column.numeric ? 'wwa-table-align-right' : '',
                    column.headerClassName || '',
                  ]
                    .filter(Boolean)
                    .join(' ')}
                  style={column.width ? { width: column.width } : undefined}
                  scope="col"
                >
                  {column.header}
                </th>
              ))}
              {hasActions ? <th className="wwa-table-align-right">{actionsLabel}</th> : null}
            </tr>
          </thead>
          <tbody>
            {loading
              ? Array.from({ length: skeletonCount }).map((_, index) => (
                  <tr key={`skeleton-${index}`} className="wwa-data-table__loading-row">
                    {columns.map((column) => (
                      <td key={column.key}>
                        <div className="wwa-data-table__cell-skeleton wwa-skeleton" />
                      </td>
                    ))}
                    {hasActions ? (
                      <td className="wwa-table-align-right">
                        <div className="wwa-data-table__action-skeleton wwa-skeleton" />
                      </td>
                    ) : null}
                  </tr>
                ))
              : null}
            {!loading && rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length + (hasActions ? 1 : 0)} className="wwa-data-table__empty-cell">
                  <EmptyState icon={emptyIcon} title={emptyTitle} message={emptyMessage} />
                </td>
              </tr>
            ) : null}
            {!loading
              ? rows.map((row, rowIndex) => {
                  const rowKey = getRowKey ? getRowKey(row, rowIndex) : row.id || rowIndex;
                  const isSelected = selectedRowKey !== undefined && selectedRowKey === rowKey;
                  const interactive = Boolean(onRowClick);

                  return (
                    <tr
                      key={rowKey}
                      className={`${isSelected ? 'wwa-row-selected' : ''} ${interactive ? 'wwa-data-table__row-clickable' : ''}`.trim()}
                      onClick={interactive ? () => onRowClick(row, rowIndex) : undefined}
                      onKeyDown={
                        interactive
                          ? (event) => {
                              if (event.key === 'Enter' || event.key === ' ') {
                                event.preventDefault();
                                onRowClick(row, rowIndex);
                              }
                            }
                          : undefined
                      }
                      tabIndex={interactive ? 0 : undefined}
                    >
                      {columns.map((column) => {
                        const content = column.render ? column.render(row, rowIndex) : row[column.key];

                        return (
                          <td
                            key={column.key}
                            className={[
                              column.align === 'right' || column.numeric ? 'wwa-table-align-right' : '',
                              column.cellClassName || '',
                            ]
                              .filter(Boolean)
                              .join(' ')}
                          >
                            {content}
                          </td>
                        );
                      })}
                      {hasActions ? (
                        <td className="wwa-table-align-right">
                          <div className="wwa-data-table__actions" onClick={(event) => event.stopPropagation()}>
                            {renderRowActions(row, rowIndex)}
                          </div>
                        </td>
                      ) : null}
                    </tr>
                  );
                })
              : null}
          </tbody>
        </table>
      </div>
      {!loading && pagination ? <TablePagination {...pagination} /> : null}
    </div>
  );
}

export default DataTable;
