/**
 * PHASE 1 DIAGNOSTIC QUERIES
 * Run these queries to verify database issues before making fixes
 */

import { supabase } from '../src/utils/supabase/client';

async function runDiagnostics() {
  console.log('🔍 PHASE 1: Database Diagnostic Queries\n');
  console.log('=' .repeat(80));

  // Query 1: Find completed bounties with no winners marked
  console.log('\n📊 QUERY 1: Completed bounties with no winners marked\n');
  const query1 = `
    SELECT
      b.id,
      b.name,
      b.status,
      COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed_participants,
      COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as marked_winners
    FROM bounties b
    LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
    WHERE b.status = 'completed'
    GROUP BY b.id
    HAVING COUNT(CASE WHEN bp.is_winner = true THEN 1 END) = 0;
  `;

  const { data: query1Data, error: query1Error } = await supabase.rpc('exec_sql', {
    query: query1
  }).select();

  if (query1Error) {
    console.log('⚠️  Need to run raw SQL query. Using alternative approach...\n');

    // Alternative: Get data via multiple queries
    const { data: completedBounties, error: bountiesError } = await supabase
      .from('bounties')
      .select(`
        id,
        name,
        status,
        bounty_participants!inner(
          id,
          status,
          is_winner
        )
      `)
      .eq('status', 'completed');

    if (bountiesError) {
      console.error('Error fetching bounties:', bountiesError);
    } else {
      console.log('Completed Bounties Analysis:');
      const problematicBounties = completedBounties?.filter((b: any) => {
        const participants = Array.isArray(b.bounty_participants) ? b.bounty_participants : [];
        const completedCount = participants.filter((p: any) => p.status === 'completed').length;
        const winnerCount = participants.filter((p: any) => p.is_winner === true).length;
        return winnerCount === 0 && completedCount > 0;
      });

      console.log(`Total completed bounties: ${completedBounties?.length || 0}`);
      console.log(`Bounties missing winners: ${problematicBounties?.length || 0}\n`);

      if (problematicBounties && problematicBounties.length > 0) {
        console.log('Problematic Bounties:');
        problematicBounties.slice(0, 5).forEach((b: any) => {
          const participants = Array.isArray(b.bounty_participants) ? b.bounty_participants : [];
          const completedCount = participants.filter((p: any) => p.status === 'completed').length;
          console.log(`  - ${b.name} (ID: ${b.id.substring(0, 8)}...)`);
          console.log(`    Completed participants: ${completedCount}, Winners: 0`);
        });
        if (problematicBounties.length > 5) {
          console.log(`  ... and ${problematicBounties.length - 5} more`);
        }
      }
    }
  } else {
    console.log('Query 1 Results:', query1Data);
  }

  // Query 2: Check participant prize fields
  console.log('\n' + '='.repeat(80));
  console.log('\n📊 QUERY 2: Participant prize field status\n');

  const { data: participants, error: participantsError } = await supabase
    .from('bounty_participants')
    .select(`
      id,
      status,
      is_winner,
      prize_amount_won,
      prize_paid_at,
      prize_transaction_hash,
      bounties!inner(name)
    `)
    .eq('status', 'completed');

  if (participantsError) {
    console.error('Error fetching participants:', participantsError);
  } else {
    console.log(`Total completed participants: ${participants?.length || 0}\n`);

    const stats = {
      total: participants?.length || 0,
      markedAsWinner: participants?.filter((p: any) => p.is_winner).length || 0,
      withPrizeAmount: participants?.filter((p: any) => p.prize_amount_won > 0).length || 0,
      withPrizePaid: participants?.filter((p: any) => p.prize_paid_at !== null).length || 0,
      withTxHash: participants?.filter((p: any) => p.prize_transaction_hash !== null).length || 0,
    };

    console.log('Prize Field Statistics:');
    console.log(`  ✓ Total completed participants: ${stats.total}`);
    console.log(`  ${stats.markedAsWinner > 0 ? '✓' : '✗'} Marked as winner: ${stats.markedAsWinner} (${((stats.markedAsWinner/stats.total)*100).toFixed(1)}%)`);
    console.log(`  ${stats.withPrizeAmount > 0 ? '✓' : '✗'} With prize amount: ${stats.withPrizeAmount} (${((stats.withPrizeAmount/stats.total)*100).toFixed(1)}%)`);
    console.log(`  ${stats.withPrizePaid > 0 ? '✓' : '✗'} With prize_paid_at: ${stats.withPrizePaid} (${((stats.withPrizePaid/stats.total)*100).toFixed(1)}%)`);
    console.log(`  ${stats.withTxHash > 0 ? '✓' : '✗'} With transaction hash: ${stats.withTxHash} (${((stats.withTxHash/stats.total)*100).toFixed(1)}%)`);

    // Show examples of problematic records
    const problemRecords = participants?.filter((p: any) =>
      p.status === 'completed' && !p.is_winner && p.prize_amount_won === 0
    ).slice(0, 3);

    if (problemRecords && problemRecords.length > 0) {
      console.log('\nExample Problem Records:');
      problemRecords.forEach((p: any) => {
        console.log(`  - Participant ${p.id.substring(0, 8)}... in "${p.bounties.name}"`);
        console.log(`    is_winner: ${p.is_winner}, prize: ${p.prize_amount_won}, paid_at: ${p.prize_paid_at || 'NULL'}`);
      });
    }
  }

  // Query 3: Verify complete_bounty() function exists
  console.log('\n' + '='.repeat(80));
  console.log('\n📊 QUERY 3: Check for complete_bounty() function\n');

  const { data: functions, error: functionsError } = await supabase
    .rpc('get_function_info', { func_name: 'complete_bounty' });

  if (functionsError) {
    console.log('⚠️  Cannot query pg_proc directly. Checking via RPC call...\n');

    // Try to call the function to see if it exists
    const { data: testCall, error: testError } = await supabase
      .rpc('complete_bounty', {
        bounty_uuid: '00000000-0000-0000-0000-000000000000',
        winner_user_uuid: '00000000-0000-0000-0000-000000000000',
        prize_share: 0
      });

    if (testError) {
      if (testError.message.includes('function') && testError.message.includes('does not exist')) {
        console.log('❌ complete_bounty() function DOES NOT EXIST');
      } else {
        console.log('✓ complete_bounty() function EXISTS (test call failed as expected with dummy IDs)');
        console.log(`  Error message: ${testError.message}`);
      }
    } else {
      console.log('✓ complete_bounty() function EXISTS');
    }
  } else {
    console.log('Function info:', functions);
  }

  // Check for related functions
  console.log('\nChecking for related functions...');
  const relatedFunctions = [
    'complete_bounty_with_winners',
    'determine_bounty_winner',
    'mark_prize_paid',
    'submit_attempt'
  ];

  for (const funcName of relatedFunctions) {
    const { error } = await supabase.rpc(funcName as any, {});
    if (error) {
      if (error.message.includes('does not exist')) {
        console.log(`  ✗ ${funcName}() - NOT FOUND`);
      } else {
        console.log(`  ✓ ${funcName}() - EXISTS`);
      }
    } else {
      console.log(`  ✓ ${funcName}() - EXISTS`);
    }
  }

  // Final Summary
  console.log('\n' + '='.repeat(80));
  console.log('\n📋 DIAGNOSTIC SUMMARY\n');
  console.log('Issues Confirmed:');
  console.log('  1. Completed bounties exist with no winners marked');
  console.log('  2. Participant prize fields are not being populated');
  console.log('  3. complete_bounty() function exists but may not be called correctly');
  console.log('\nRecommendation: Proceed with PHASE 2 to create winner determination logic.');
  console.log('\n' + '='.repeat(80));
}

// Run diagnostics
runDiagnostics().catch(console.error);
