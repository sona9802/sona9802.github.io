import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL?.trim()
const publishableKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim()

export const phase2Configured = Boolean(url && publishableKey)
export const phase2Enabled = import.meta.env.VITE_PHASE2_ENABLED === 'true' && phase2Configured

export const supabase = phase2Configured
  ? createClient(url, publishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null
