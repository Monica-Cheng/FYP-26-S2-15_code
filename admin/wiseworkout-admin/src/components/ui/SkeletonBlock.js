import React from 'react';

function SkeletonBlock({ height = 140, style }) {
  return <div className="wwa-skeleton" style={{ height, ...style }} />;
}

export default SkeletonBlock;
