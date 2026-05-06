/**
 * Send a NUI callback to FiveM. Uses 'peak-sprays' as the resource name.
 */
export function fetchNui(eventName: string, data: Record<string, unknown> = {}): Promise<any> {
  const resourceName = (window as any).GetParentResourceName ? (window as any).GetParentResourceName() : 'peak-sprays'
  return fetch(`https://${resourceName}/${eventName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
    .then(resp => resp.json())
    .catch(() => { })
}
