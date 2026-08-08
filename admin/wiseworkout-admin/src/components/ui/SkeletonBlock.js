import React from 'react';

function SkeletonBlock({ height = 140, style, className = '' }) {
  return <div className={`wwa-skeleton ${className}`.trim()} style={{ height, ...style }} />;
}

export default SkeletonBlock;
