import { ref } from 'vue'

const isDark = ref(document.documentElement.classList.contains('dark'))

export function useTheme() {
  function toggle() {
    isDark.value = !isDark.value
    document.documentElement.classList.toggle('dark', isDark.value)
    try { localStorage.setItem('tv-theme', isDark.value ? 'dark' : 'light') } catch { /* ignore */ }
  }
  return { isDark, toggle }
}
