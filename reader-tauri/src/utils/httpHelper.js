export const API_BASE = 'https://www.huijuguangnian.top:8068'

/**
 * HTTP request helpers.
 * Adds auth headers and logs the user out when protected API calls fail.
 */

let logoutCallback = null
let isLoggingOut = false

export function setLogoutCallback(callback) {
  logoutCallback = callback
}

export function getAuthToken() {
  return localStorage.getItem('auth_token_full') || localStorage.getItem('auth_token')
}

function triggerLogout() {
  if (isLoggingOut || !getAuthToken()) return

  isLoggingOut = true
  try {
    if (logoutCallback) {
      logoutCallback()
    } else {
      localStorage.removeItem('auth_token')
      localStorage.removeItem('auth_token_full')
      localStorage.removeItem('username')
    }
  } finally {
    setTimeout(() => {
      isLoggingOut = false
    }, 0)
  }
}

export function createAuthHeaders(options = {}) {
  const token = getAuthToken()
  const isFormData = typeof FormData !== 'undefined' && options.body instanceof FormData

  const headers = {
    ...options.headers
  }

  if (!isFormData && !headers['Content-Type']) {
    headers['Content-Type'] = 'application/json'
  }

  if (token) {
    headers.Authorization = token.startsWith('Bearer ') ? token : `Bearer ${token}`
  }

  return {
    ...options,
    headers
  }
}

function checkAuthError(response, url) {
  // Bookstore also returns 403 for anonymous access. The quota endpoint admits every signed-in role.
  const quotaDenied = response.status === 403 && new URL(url, location.href).pathname === '/api/storage/quota'
  if (response.status === 401 || quotaDenied) {
    triggerLogout()
  }
}

export async function authFetch(url, options = {}) {
  const session = getAuthToken()
  const authOptions = createAuthHeaders(options)

  const response = await fetch(url, authOptions)
  if (session === getAuthToken()) checkAuthError(response, url)
  return response
}
