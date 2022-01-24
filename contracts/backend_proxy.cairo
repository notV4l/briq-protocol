%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.starknet.common.syscalls import call_contract, delegate_l1_handler, delegate_call

from contracts.proxy.library import (
    Proxy_implementation_address,
    Proxy_set_implementation,
    Proxy_initializer
)

####################
####################
####################
# Backend proxies don't delegate the calls, but instead call.
# This is because the backend proxy handles authorization,
# the actual backend contract only checks that its caller is the proxy.

func _constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (owner: felt):
    Proxy_initializer(owner)
    return ()
end

@external
func setImplementation{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(new_implementation: felt):
    Proxy_set_implementation(new_implementation)
    return()
end

####################
####################
####################
# Authorization patterns

func _onlyAdmin{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } ():
    let (caller) = get_caller_address()
    if (caller - 0x123456) == 0:
        return ()
    end
    # Failure
    assert 0 = 1
    return ()
end

func _onlyAdminAnd{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (address: felt):
    let (caller) = get_caller_address()
    if (caller - address) == 0:
        return ()
    end
    _onlyAdmin()
    return ()
end

####################
####################
####################
# Forwarded calls

## Fallback method - can be called by admins.
@external
@raw_input
@raw_output
func __default__{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        selector: felt,
        calldata_size: felt,
        calldata: felt*
    ) -> (
        retdata_size: felt,
        retdata: felt*
    ):
    _onlyAdmin()

    let (address) = Proxy_implementation_address.read()

    let (retdata_size: felt, retdata: felt*) = call_contract(
        contract_address=address,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata
    )

    return (retdata_size=retdata_size, retdata=retdata)
end

## TODO: L1 handler