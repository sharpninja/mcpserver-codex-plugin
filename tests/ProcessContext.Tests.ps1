#Requires -Version 7.0

# Increment A: identical cases feed the reference adapter and real process-context adapter.
# The callbacks model MCP resolve/getPolicy replies. The oracle has explicit bad-result controls.
Describe 'Increment A process manifest and exact policy contract' -Tag @('IncrementA', 'ManifestMock', 'PolicyMock') {
    BeforeAll {
        $script:PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
        $script:ProcessModule = Join-Path $script:PluginRoot 'lib/process-context.ps1'
        $script:Workspace = 'F:\Fixture'
        $script:Todo = 'PLAN-FIXTURE-001'
        $script:Text = 'Exact policy bytes for the approved process.'
        $script:Digest = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($script:Text))
        )
        # BDPv4 fixture mirrors the approved B5 eight-stage graph. Policy bytes below
        # are test-double data; the live canonical memory is separately source-pinned.
        $script:GraphA = @(
            @{ id = 'requirements-ac-ready'; predecessorGateIds = @() },
            @{ id = 'tests-written'; predecessorGateIds = @('requirements-ac-ready') },
            @{ id = 'mock-validated'; predecessorGateIds = @('tests-written') },
            @{ id = 'real-implementation-allowed'; predecessorGateIds = @('mock-validated') },
            @{ id = 'real-green'; predecessorGateIds = @('real-implementation-allowed') },
            @{ id = 'full-suite-green'; predecessorGateIds = @('real-green') },
            @{ id = 'hostile-validation'; predecessorGateIds = @('full-suite-green') },
            @{ id = 'done'; predecessorGateIds = @('hostile-validation') }
        )
        $script:GraphB = @(
            @{ id = 'proposal'; predecessorGateIds = @() },
            @{ id = 'peer-vote'; predecessorGateIds = @('proposal-approved') },
            @{ id = 'publish'; predecessorGateIds = @('peer-vote-approved') }
        )
        $script:Ref = @{
            id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'global'
            source = 'mcp'; snapshotId = 'snapshot-002'; sha256 = $script:Digest
        }
        $script:Policy = @{
            id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'global'
            source = 'mcp'; snapshotId = 'snapshot-002'; text = $script:Text
        }

        function New-Reply {
            param(
                [string]$State = 'Assigned',
                [string]$Methodology = 'BDPv4',
                [int]$Revision = 7,
                [array]$Graph = $script:GraphA,
                [bool]$Signed = $true,
                [array]$Refs = @($script:Ref)
            )
            return @{
                status = 'ok'; assignmentState = $State; signedApproval = $Signed
                bindingId = 'binding-' + $Methodology; bindingRevision = $Revision
                methodologyId = $Methodology; manifestId = 'manifest-' + $Methodology
                manifestDigest = 'digest-' + $Methodology
                approvalReceiptId = 'approval-fixture-001'
                phaseGraph = $Graph; policyRefs = $Refs
            }
        }

        function New-Case {
            param(
                [object]$Reply = (New-Reply),
                [object]$PolicyReply = @{ status = 'ok'; items = @($script:Policy) },
                [scriptblock]$ResolveOverride,
                [scriptblock]$FetchOverride
            )
            $resolvedReply = $Reply
            $fetchedReply = $PolicyReply
            if (-not $ResolveOverride) {
                $ResolveOverride = { param($workspace, $todo, $slice) return $resolvedReply }.GetNewClosure()
            }
            if (-not $FetchOverride) {
                $FetchOverride = { param($bindingId, $policyId) return $fetchedReply }.GetNewClosure()
            }
            $innerResolve = $ResolveOverride
            $innerFetch = $FetchOverride
            $expectedWorkspace = $script:Workspace
            $expectedTodo = $script:Todo
            $expectedPolicyId = $script:Ref.id
            $spy = [pscustomobject]@{
                resolveCalls = 0
                fetchCalls = 0
                requestedWorkspace = ''
                requestedTodo = ''
                requestedBinding = ''
                requestedPolicy = ''
                resolvedBinding = ''
            }
            $checkedResolve = {
                param($workspace, $todo, $slice)
                $spy.resolveCalls++
                $spy.requestedWorkspace = $workspace
                $spy.requestedTodo = $todo
                if ($workspace -cne $expectedWorkspace -or $todo -cne $expectedTodo) {
                    throw [InvalidOperationException]::new('wrong resolve identity')
                }
                $response = & $innerResolve $workspace $todo $slice
                if ($null -ne $response) { $spy.resolvedBinding = [string]$response.bindingId }
                return $response
            }.GetNewClosure()
            $checkedFetch = {
                param($bindingId, $policyId)
                $spy.fetchCalls++
                $spy.requestedBinding = $bindingId
                $spy.requestedPolicy = $policyId
                if ($bindingId -cne $spy.resolvedBinding -or $policyId -cne $expectedPolicyId) {
                    throw [InvalidOperationException]::new('wrong policy fetch identity')
                }
                return (& $innerFetch $bindingId $policyId)
            }.GetNewClosure()
            return @{ resolve = $checkedResolve; fetchPolicy = $checkedFetch; spy = $spy }
        }

        function Invoke-AdapterDouble {
            param([hashtable]$Case, [string]$Slice)
            try {
                $binding = & $Case.resolve $script:Workspace $script:Todo $Slice
            } catch {
                return @{ status = 'PROCESS_CONTEXT_UNAVAILABLE'; assignmentState = 'Unavailable' }
            }
            if ($null -eq $binding -or $binding.status -ne 'ok' -or
                $binding.assignmentState -notin @('Assigned', 'ExplicitlyUnmanaged') -or
                $binding.signedApproval -isnot [bool] -or -not $binding.signedApproval -or
                [string]::IsNullOrWhiteSpace([string]$binding.approvalReceiptId) -or
                [string]::IsNullOrWhiteSpace([string]$binding.bindingId) -or
                $binding.bindingRevision -isnot [int] -or $binding.bindingRevision -lt 1 -or
                [string]::IsNullOrWhiteSpace([string]$binding.manifestId) -or
                [string]::IsNullOrWhiteSpace([string]$binding.manifestDigest)) {
                return @{ status = 'PROCESS_CONTEXT_UNAVAILABLE'; assignmentState = 'Unavailable' }
            }
            $result = @{
                status = 'ok'; assignmentState = $binding.assignmentState
                methodologyId = $binding.methodologyId
                bindingRevision = $binding.bindingRevision
                manifestId = $binding.manifestId
                manifestDigest = $binding.manifestDigest
                phaseGraph = $binding.phaseGraph
            }
            if ($binding.assignmentState -eq 'ExplicitlyUnmanaged') { return $result }
            if (@($binding.phaseGraph).Count -eq 0 -or @($binding.policyRefs).Count -ne 1) {
                return @{ status = 'PROCESS_POLICY_STALE'; assignmentState = 'Unavailable' }
            }
            $ref = $binding.policyRefs[0]
            try {
                $reply = & $Case.fetchPolicy $binding.bindingId $ref.id
            } catch {
                return @{ status = 'PROCESS_CONTEXT_UNAVAILABLE'; assignmentState = 'Unavailable' }
            }
            $items = @()
            if ($null -ne $reply -and $null -ne $reply.items) { $items = @($reply.items) }
            if ($reply.status -ne 'ok' -or $items.Count -ne 1) {
                return @{ status = 'PROCESS_POLICY_STALE'; assignmentState = 'Unavailable' }
            }
            $policy = $items[0]
            $digest = [Convert]::ToHexString(
                [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$policy.text))
            )
            if ($policy.id -cne $ref.id -or $policy.version -cne $ref.version -or
                $policy.scope -cne $ref.scope -or $policy.source -cne $ref.source -or
                $policy.snapshotId -cne $ref.snapshotId -or $digest -cne $ref.sha256) {
                return @{ status = 'PROCESS_POLICY_STALE'; assignmentState = 'Unavailable' }
            }
            $result.policyId = $policy.id
            $result.policyVersion = $policy.version
            $result.policySource = $policy.source
            $result.policySnapshotId = $policy.snapshotId
            $result.policySha256 = $digest
            $result.policyText = $policy.text
            return $result
        }

        function Invoke-Target {
            param([hashtable]$Case, [string]$Slice = 'slice-1')
            if ($env:MCP_PROCESS_TEST_TARGET -eq 'real') {
                if (-not (Test-Path -LiteralPath $script:ProcessModule -PathType Leaf)) {
                    throw "Increment A real implementation missing: $script:ProcessModule"
                }
                . $script:ProcessModule
                return Resolve-McpProcessContext -WorkspacePath $script:Workspace -TodoId $script:Todo -SliceId $Slice -ResolveOverride $Case.resolve -PolicyOverride $Case.fetchPolicy
            }
            return Invoke-AdapterDouble -Case $Case -Slice $Slice
        }

        function Assert-Result {
            param([hashtable]$Actual, [string]$Status, [string]$State,
                  [string]$Methodology = '', [int]$Revision = -1, [array]$Graph)
            $Actual.status | Should -BeExactly $Status
            $Actual.assignmentState | Should -BeExactly $State
            if ($Methodology) { $Actual.methodologyId | Should -BeExactly $Methodology }
            if ($Revision -ge 0 -and $Actual.bindingRevision -ne $Revision) {
                throw [InvalidOperationException]::new('contract:bindingRevision')
            }
            if ($null -ne $Graph) {
                $actualGraph = $Actual.phaseGraph | ConvertTo-Json -Depth 8 -Compress
                $expectedGraph = $Graph | ConvertTo-Json -Depth 8 -Compress
                if ($actualGraph -cne $expectedGraph) {
                    throw [InvalidOperationException]::new('contract:phaseGraph')
                }
            }
            if ($State -eq 'Assigned') {
                $Actual.policyId | Should -BeExactly $script:Ref.id
                $Actual.policyVersion | Should -BeExactly $script:Ref.version
                $Actual.policySource | Should -BeExactly $script:Ref.source
                $Actual.policySnapshotId | Should -BeExactly $script:Ref.snapshotId
                if ($Actual.policySha256 -cne $script:Digest) {
                    throw [InvalidOperationException]::new('contract:policySha256')
                }
                $Actual.policyText | Should -BeExactly $script:Text
            }
        }
    }

    It 'uses the approved methodology, revision, and phase graph' {
        $case = New-Case
        Assert-Result (Invoke-Target $case) 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA
        $case.spy.resolveCalls | Should -Be 1
        $case.spy.fetchCalls | Should -Be 1
        $case.spy.requestedWorkspace | Should -BeExactly $script:Workspace
        $case.spy.requestedTodo | Should -BeExactly $script:Todo
        $case.spy.requestedBinding | Should -BeExactly 'binding-BDPv4'
        $case.spy.requestedPolicy | Should -BeExactly $script:Ref.id
    }

    It 'handles a materially different process graph without special-case code' {
        $case = New-Case -Reply (New-Reply -Methodology 'review-flow' -Graph $script:GraphB)
        Assert-Result (Invoke-Target $case) 'ok' 'Assigned' 'review-flow' 7 $script:GraphB
        ($script:GraphA | ConvertTo-Json -Depth 8 -Compress) |
            Should -Not -BeExactly ($script:GraphB | ConvertTo-Json -Depth 8 -Compress)
    }

    It 'keeps an active slice pinned while a new slice uses the next approved revision' {
        $store = @{
            latest = New-Reply -Revision 7
            pins = @{}
        }
        $next = New-Reply -Revision 8 -Methodology 'review-flow' -Graph $script:GraphB
        $resolve = {
            param($workspace, $todo, $slice)
            if (-not $store.pins.ContainsKey($slice)) {
                $store.pins[$slice] = $store.latest
            }
            return $store.pins[$slice]
        }.GetNewClosure()
        $case = New-Case -ResolveOverride $resolve
        Assert-Result (Invoke-Target $case 'slice-1') 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA
        $store.latest = $next
        Assert-Result (Invoke-Target $case 'slice-1') 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA
        Assert-Result (Invoke-Target $case 'slice-2') 'ok' 'Assigned' 'review-flow' 8 $script:GraphB
        $case.spy.resolveCalls | Should -Be 3
    }

    It 'never interprets missing, ambiguous, or failed resolution as unmanaged' {
        foreach ($reply in @(
            $null,
            @{ status = 'PROCESS_CONTEXT_UNAVAILABLE'; assignmentState = 'Unavailable' },
            @{ status = 'ambiguous'; assignmentState = 'Assigned' }
        )) {
            Assert-Result (Invoke-Target (New-Case -Reply $reply)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'
        }
        $case = New-Case -ResolveOverride { throw 'MCP unavailable' }
        Assert-Result (Invoke-Target $case) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'
    }

    It 'requires signed approval for explicit unmanaged assignment' {
        Assert-Result (Invoke-Target (New-Case -Reply (New-Reply -State 'ExplicitlyUnmanaged'))) 'ok' 'ExplicitlyUnmanaged' 'BDPv4' 7
        Assert-Result (Invoke-Target (New-Case -Reply (New-Reply -State 'ExplicitlyUnmanaged' -Signed $false))) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'
    }

    It 'rejects forged or incomplete unmanaged assignment provenance' {
        $forged = New-Reply -State 'ExplicitlyUnmanaged'
        $forged.signedApproval = 'false'
        Assert-Result (Invoke-Target (New-Case -Reply $forged)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'

        $noBinding = New-Reply -State 'ExplicitlyUnmanaged'
        $noBinding.Remove('bindingId')
        Assert-Result (Invoke-Target (New-Case -Reply $noBinding)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'

        $noRevision = New-Reply -State 'ExplicitlyUnmanaged'
        $noRevision.Remove('bindingRevision')
        Assert-Result (Invoke-Target (New-Case -Reply $noRevision)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'

        $noManifest = New-Reply -State 'ExplicitlyUnmanaged'
        $noManifest.Remove('manifestDigest')
        Assert-Result (Invoke-Target (New-Case -Reply $noManifest)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'

        $noReceipt = New-Reply -State 'ExplicitlyUnmanaged'
        $noReceipt.Remove('approvalReceiptId')
        Assert-Result (Invoke-Target (New-Case -Reply $noReceipt)) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'
    }

    It 'accepts exact policy ID, version, scope, source, immutable snapshot, and SHA-256' {
        Assert-Result (Invoke-Target (New-Case)) 'ok' 'Assigned' 'BDPv4' 7
    }

    It 'rejects missing, duplicate, and near-match policy IDs' {
        foreach ($items in @(
            @(),
            @($script:Policy, $script:Policy),
            @(@{ id = 'MEMORY-FLOW-01'; version = 'v2'; scope = 'global'; source = 'mcp'; snapshotId = 'snapshot-002'; text = $script:Text })
        )) {
            $case = New-Case -PolicyReply @{ status = 'ok'; items = $items }
            Assert-Result (Invoke-Target $case) 'PROCESS_POLICY_STALE' 'Unavailable'
        }
    }

    It 'rejects wrong version, scope, source, snapshot identity, and changed bytes' {
        foreach ($policy in @(
            @{ id = 'MEMORY-FLOW-001'; version = 'v3'; scope = 'global'; source = 'mcp'; snapshotId = 'snapshot-002'; text = $script:Text },
            @{ id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'todo'; source = 'mcp'; snapshotId = 'snapshot-002'; text = $script:Text },
            @{ id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'global'; source = 'github'; snapshotId = 'snapshot-002'; text = $script:Text },
            @{ id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'global'; source = 'mcp'; snapshotId = 'snapshot-003'; text = $script:Text },
            @{ id = 'MEMORY-FLOW-001'; version = 'v2'; scope = 'global'; source = 'mcp'; snapshotId = 'snapshot-002'; text = 'Exact policy bytes for approved process.' }
        )) {
            Assert-Result (Invoke-Target (New-Case -PolicyReply @{ status = 'ok'; items = @($policy) })) 'PROCESS_POLICY_STALE' 'Unavailable'
        }
    }

    It 'distinguishes confirmed missing policy from policy transport failure' {
        Assert-Result (Invoke-Target (New-Case -PolicyReply @{ status = 'confirmed_not_found'; items = @() })) 'PROCESS_POLICY_STALE' 'Unavailable'
        Assert-Result (Invoke-Target (New-Case -FetchOverride { throw 'MCP unavailable' })) 'PROCESS_CONTEXT_UNAVAILABLE' 'Unavailable'
    }

    It 'proves the oracle rejects a wrong phase graph, revision, and policy digest' {
        $good = @{
            status = 'ok'; assignmentState = 'Assigned'; methodologyId = 'BDPv4'
            bindingRevision = 7; phaseGraph = $script:GraphA
            policyId = $script:Ref.id; policyVersion = 'v2'; policySource = 'mcp'
            policySnapshotId = 'snapshot-002'; policySha256 = $script:Digest; policyText = $script:Text
        }
        Assert-Result $good 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA
        $wrongRevision = $good.Clone()
        $wrongRevision.bindingRevision = 6
        { Assert-Result $wrongRevision 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA } |
            Should -Throw -ExpectedMessage 'contract:bindingRevision'
        $wrongGraph = $good.Clone()
        $wrongGraph.phaseGraph = $script:GraphB
        { Assert-Result $wrongGraph 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA } |
            Should -Throw -ExpectedMessage 'contract:phaseGraph'
        $wrongDigest = $good.Clone()
        $wrongDigest.policySha256 = '0000'
        { Assert-Result $wrongDigest 'ok' 'Assigned' 'BDPv4' 7 $script:GraphA } |
            Should -Throw -ExpectedMessage 'contract:policySha256'
    }
}

