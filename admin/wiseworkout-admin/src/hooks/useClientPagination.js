import { useEffect, useMemo, useState } from 'react';

export const DEFAULT_PAGE_SIZE = 20;
export const PAGE_SIZE_OPTIONS = [10, 20, 50];

function useClientPagination(items, options = {}) {
  const {
    defaultPageSize = DEFAULT_PAGE_SIZE,
    pageSizeOptions = PAGE_SIZE_OPTIONS,
    resetKey = '',
  } = options;

  const initialPageSize = pageSizeOptions.includes(defaultPageSize)
    ? defaultPageSize
    : pageSizeOptions[0] || DEFAULT_PAGE_SIZE;

  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(initialPageSize);

  useEffect(() => {
    setCurrentPage(1);
  }, [pageSize, resetKey]);

  const totalItems = items.length;

  const totalPages = useMemo(() => {
    if (totalItems === 0) return 1;
    return Math.max(1, Math.ceil(totalItems / pageSize));
  }, [pageSize, totalItems]);

  useEffect(() => {
    setCurrentPage((prev) => {
      if (prev > totalPages) return totalPages;
      if (prev < 1) return 1;
      return prev;
    });
  }, [totalPages]);

  const paginatedItems = useMemo(() => {
    if (totalItems === 0) return [];
    const start = (currentPage - 1) * pageSize;
    return items.slice(start, start + pageSize);
  }, [currentPage, items, pageSize, totalItems]);

  return {
    currentPage,
    pageSize,
    setCurrentPage,
    setPageSize,
    totalItems,
    totalPages,
    paginatedItems,
    pageSizeOptions,
  };
}

export default useClientPagination;
