// Signal Cleanup Edge Function
// Runs every 20 minutes to delete abandoned signals
// Preserves signals newer than 2 minutes (active calls)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
    // Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Initialize Supabase client with service role key
        const supabaseUrl = Deno.env.get('https://luzazzyqihpertxteokq.supabase.co')!
        const supabaseServiceKey = Deno.env.get('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1emF6enlxaWhwZXJ0eHRlb2txIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzMDE2MzMsImV4cCI6MjA4NDg3NzYzM30.hkCVI2w5Hx9gIhdKh53u-JrFWB3oXuOEf6ZkQzAIRu0')!

        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // Calculate threshold: 2 minutes ago
        // Signals older than this are considered abandoned
        const thresholdDate = new Date(Date.now() - 2 * 60 * 1000)
        const thresholdISO = thresholdDate.toISOString()

        console.log(`[Cleanup] Running signal cleanup at ${new Date().toISOString()}`)
        console.log(`[Cleanup] Deleting signals older than ${thresholdISO}`)

        // Count signals before deletion (for logging)
        const { count: beforeCount } = await supabase
            .from('signals')
            .select('*', { count: 'exact', head: true })

        // Delete only abandoned signals (older than 2 minutes)
        // This preserves:
        // - Active ICE candidates being exchanged
        // - Recent offers/answers in progress
        // - Fresh pings for incoming calls
        const { data, error } = await supabase
            .from('signals')
            .delete()
            .lt('created_at', thresholdISO)
            .select('id')

        if (error) {
            console.error('[Cleanup] Error deleting signals:', error)
            throw error
        }

        const deletedCount = data?.length ?? 0

        // Count signals after deletion
        const { count: afterCount } = await supabase
            .from('signals')
            .select('*', { count: 'exact', head: true })

        console.log(`[Cleanup] Complete!`)
        console.log(`[Cleanup] Before: ${beforeCount ?? 0} signals`)
        console.log(`[Cleanup] Deleted: ${deletedCount} abandoned signals`)
        console.log(`[Cleanup] After: ${afterCount ?? 0} signals`)

        return new Response(
            JSON.stringify({
                success: true,
                deleted: deletedCount,
                before: beforeCount ?? 0,
                after: afterCount ?? 0,
                threshold: thresholdISO,
                timestamp: new Date().toISOString(),
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            }
        )
    } catch (error) {
        console.error('[Cleanup] Fatal error:', error)

        return new Response(
            JSON.stringify({
                success: false,
                error: error.message,
                timestamp: new Date().toISOString(),
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 500,
            }
        )
    }
})
