{{ 
    config(
        materialized='incremental',
        
        alias = 'transactions',
        partition_by = ['block_month'],
        unique_key = ['block_date', 'tx_hash', 'trace_address'], 
        file_format ='delta',
        incremental_strategy='merge',
        post_hook='{{ expose_spells(\'["ethereum"]\',
                                    "project",
                                    "safe",
                                    \'["tschubotz", "hosuke"]\') }}'
    ) 
}}

select 
    'ethereum' as blockchain,
    try_cast(date_trunc('day', tr.block_time) as date) as block_date,
    CAST(date_trunc('month', tr.block_time) as DATE) as block_month,
    tr.block_time,
    tr.block_number,
    tr.tx_hash,
    s.address,
    tr.to,
    tr.value,
    tr.gas,
    tr.gas_used,
    tr.tx_index,
    tr.sub_traces,
    tr.trace_address,
    tr.success,
    tr.error,
    tr.code,
    tr.input,
    tr.output,
    case 
        when bytearray_substring(tr.input, 1, 4) = 0x6a761202 then 'execTransaction'
        when bytearray_substring(tr.input, 1, 4) = 0x468721a7 then 'execTransactionFromModule'
        when bytearray_substring(tr.input, 1, 4) = 0x5229073f then 'execTransactionFromModuleReturnData'
        else 'unknown'
    end as method
from {{ source('ethereum', 'traces') }} tr 
join {{ ref('safe_ethereum_safes') }} s
    on s.address = tr."from"
join {{ ref('safe_ethereum_singletons') }} ss
    on tr.to = ss.address
where bytearray_substring(tr.input, 1, 4) in (
        0x6a761202, -- execTransaction
        0x468721a7, -- execTransactionFromModule
        0x5229073f -- execTransactionFromModuleReturnData
    )
    and tr.call_type = 'delegatecall'
    {% if not is_incremental() %}
    and tr.block_time > TIMESTAMP '2018-11-24' -- for initial query optimisation
    {% endif %}
    {% if is_incremental() %}
    and tr.block_time > date_trunc('day', now() - interval '7' day)
    {% endif %}
