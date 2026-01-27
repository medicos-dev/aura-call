// Signal Cleanup Edge Function
// Runs every 20 minutes to delete abandoned signals
// Preserves signals newer than 2 minutes (active calls)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

declare const Deno: any;

Deno.serve(async (req: Request) => {
    // Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Initialize Supabase client
        const supabaseUrl = 'https://luzazzyqihpertxteokq.supabase.co'
        const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1emF6enlxaWhwZXJ0eHRlb2txIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMDE2MzMsImV4cCI6MjA4NDg3NzYzM30.hkCVI2w5Hx9gIhdKh53u-JrFWB3oXuOEf6ZkQzAIRu0'

        const supabase = createClient(supabaseUrl, supabaseKey)

        // Calculate threshold: 2 minutes ago
        const thresholdDate = new Date(Date.now() - 2 * 60 * 1000)
        const thresholdISO = thresholdDate.toISOString()

        console.log(`[Cleanup] Running signal cleanup at ${new Date().toISOString()}`)

        // Delete signals that are either:
        // 1. Marked as 'processed' (completed)
        // 2. 'active' but older than 2 minutes (abandoned)
        const { data, error } = await supabase
            .from('signals')
            .delete()
            .or(`status.eq.processed,and(status.eq.active,created_at.lt.${thresholdISO})`)
            .select('id')

        if (error) {
            console.error('[Cleanup] Error deleting signals:', error)
            throw error
        }

        const deletedCount = data?.length ?? 0

        console.log(`[Cleanup] Deleted: ${deletedCount} abandoned signals`)

        return new Response(
            JSON.stringify({
                success: true,
                deleted: deletedCount,
                timestamp: new Date().toISOString(),
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            }
        )
    } catch (error: any) {
        console.error('[Cleanup] Fatal error:', error)

        return new Response(
            JSON.stringify({
                success: false,
                error: error.message || 'Unknown error',
                timestamp: new Date().toISOString(),
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 500,
            }
        )
    }
})
