%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import (
    assert_nn_le,
    assert_lt,
    assert_le,
    assert_not_zero,
    assert_lt_felt,
    assert_le_felt,
)
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc

from contracts.briq.balance_enumerability import (
    _owner,
    _balance,
    _total_supply,
    _setTokenByOwner,
    _unsetTokenByOwner,
    _setMaterialByOwner,
    _maybeUnsetMaterialByOwner,
)

from contracts.ecosystem.to_set import _set_address, getSetAddress_, setSetAddress_

from contracts.library_erc1155.transferability import ERC1155_transferability

//###########
//###########
//###########
// # Authorization patterns

from contracts.utilities.authorization import _only, _onlyAdmin, _onlyAdminAnd

func _onlySetAnd{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(address: felt) {
    let (caller) = get_caller_address();
    let (setaddr) = _set_address.read();
    if (caller == setaddr) {
        return ();
    }
    _only(address);
    return ();
}

//###########
//###########
//###########
// Admin functions

// # TODO -> mint multiple NFT

@external
func transferFT_{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    sender: felt, recipient: felt, material: felt, qty: felt
) {
    _onlySetAnd(sender);

    assert_not_zero(sender);
    assert_not_zero(recipient);
    assert_not_zero(sender - recipient);
    assert_not_zero(material);
    assert_lt_felt(material, 2 ** 64);  // Technically un-necessary, since balance would be 0
    assert_not_zero(qty);

    // FT conversion
    let briq_token_id = material;

    let (balance_sender) = _balance.read(sender, briq_token_id);
    assert_le_felt(qty, balance_sender);
    _balance.write(sender, briq_token_id, balance_sender - qty);

    let (balance) = _balance.read(recipient, briq_token_id);
    with_attr error_message("Transfer would overflow recipient balance") {
        assert_lt_felt(balance, balance + qty);
    }
    _balance.write(recipient, briq_token_id, balance + qty);

    _maybeUnsetMaterialByOwner(sender, material);
    _setMaterialByOwner(recipient, material, 0);

    let (__addr) = get_contract_address();
    ERC1155_transferability._onTransfer(__addr, sender, recipient, briq_token_id, qty);
    return ();
}

@external
func transferOneNFT_{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    sender: felt, recipient: felt, material: felt, briq_token_id: felt
) {
    alloc_locals;
    local syscall_ptr: felt* = syscall_ptr;
    _onlySetAnd(sender);

    assert_not_zero(sender);
    assert_not_zero(recipient);
    assert_not_zero(sender - recipient);
    assert_not_zero(material);

    // Technically un-necessary, balance would be 0.
    with_attr error_message("briq_token_id is not an NFT") {
        assert_lt_felt(2 ** 64, briq_token_id);
    }

    // Check that the material matches what is passed in briq_token_id.
    let b = (briq_token_id - material) / (2 ** 64);
    let is_same_mat = is_le_felt(b, 2 ** 187);
    with_attr error_message("material does not match briq_token_id") {
        assert is_same_mat = 1;
    }

    let (curr_owner) = _owner.read(briq_token_id);
    assert sender = curr_owner;
    _owner.write(briq_token_id, recipient);

    // Unset before setting, so that self-transfers work.
    _unsetTokenByOwner(sender, material, briq_token_id);
    _setTokenByOwner(recipient, material, briq_token_id, 0);

    _maybeUnsetMaterialByOwner(sender, material);  // Keep after unset token or it won't unset
    _setMaterialByOwner(recipient, material, 0);

    let (__addr) = get_contract_address();
    ERC1155_transferability._onTransfer(__addr, sender, recipient, briq_token_id, 1);

    return ();
}

func _transferNFT{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    sender: felt, recipient: felt, material: felt, index: felt, token_ids: felt*
) {
    if (index == 0) {
        return ();
    }
    transferOneNFT_(sender, recipient, material, token_ids[index - 1]);
    return _transferNFT(sender, recipient, material, index - 1, token_ids);
}

@external
func transferNFT_{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    sender: felt, recipient: felt, material: felt, token_ids_len: felt, token_ids: felt*
) {
    // Calls authorized methods, no need to check here.
    _transferNFT(sender, recipient, material, token_ids_len, token_ids);
    return ();
}
