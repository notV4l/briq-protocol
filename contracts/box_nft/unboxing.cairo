%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_lt_felt
from starkware.starknet.common.syscalls import get_caller_address

from starkware.cairo.common.registers import get_label_location

from contracts.library_erc1155.transferability import ERC1155_transferability
from contracts.library_erc1155.balance import _balance

from contracts.box_nft.data import shape_data_start, briq_data_start

from contracts.ecosystem.to_briq import _briq_address
from contracts.ecosystem.to_booklet import getBookletAddress_

from contracts.ecosystem.genesis_collection import GENESIS_COLLECTION

@contract_interface
namespace IBookletContract {
    func mint_(owner: felt, token_id: felt, shape_contract: felt) {
    }
}

@contract_interface
namespace IBriqContract {
    func mintFT_(owner: felt, material: felt, qty: felt) {
    }
}

// Unbox burns the box NFT, and mints briqs & attributes_registry corresponding to the token URI.
@external
func unbox_{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt, token_id: felt
) {
    let (balance) = _balance.read(owner, token_id);
    with_attr error_message("Insufficient balance") {
        assert_lt_felt(balance - 1, balance);
    }
    // At this point token_id cannot be 0 any more

    _balance.write(owner, token_id, balance - 1);

    let (caller) = get_caller_address();
    // Only the owner may unbox their box.
    assert owner = caller;
    ERC1155_transferability._onTransfer(caller, owner, 0, token_id, 1);

    _unbox_mint(owner, token_id);

    return ();
}

func _unbox_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt, token_id: felt
) {
    alloc_locals;

    let (_shape_data_start) = get_label_location(shape_data_start);
    let shape_contract = [cast(_shape_data_start, felt*) + token_id - 1];
    let (booklet_addr) = getBookletAddress_();
    IBookletContract.mint_(booklet_addr, owner, token_id * 2**192 + GENESIS_COLLECTION, shape_contract);

    let (_briq_data_start) = get_label_location(briq_data_start);
    let (briq_addr) = _briq_address.read();
    _maybe_mint_briq(owner, briq_addr, cast(_briq_data_start, felt*), token_id, 1, 0);
    _maybe_mint_briq(owner, briq_addr, cast(_briq_data_start, felt*), token_id, 3, 1);
    _maybe_mint_briq(owner, briq_addr, cast(_briq_data_start, felt*), token_id, 4, 2);
    _maybe_mint_briq(owner, briq_addr, cast(_briq_data_start, felt*), token_id, 5, 3);
    // TODO -> NFT briqs
    // let (amnt) = [cast(_briq_data_start, felt*) + 1]
    // IBriqContract.mintFT_(briq_addr, owner, 0x1, amnt)

    return ();
}

func _maybe_mint_briq{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    briq_addr: felt,
    _briq_data_start: felt*,
    token_id: felt,
    material: felt,
    offset: felt,
) {
    let amnt = [_briq_data_start + (token_id - 1) * 5 + offset];
    if (amnt != 0) {
        IBriqContract.mintFT_(briq_addr, owner, material, amnt);
        return ();
    } else {
        return ();
    }
}
