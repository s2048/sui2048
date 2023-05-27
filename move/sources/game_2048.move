module ethos::game_2048 {
    use std::vector;
    use std::string::{utf8};

    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext, sender};
    use sui::event;
    use sui::transfer::{transfer, public_transfer};

    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::pay;
    use sui::transfer;
    
    use sui::package;
    use sui::display;

    use ethos::game_board_2048::{Self, GameBoard2048};

    friend ethos::leaderboard_2048;

    #[test_only]
    friend ethos::game_2048_tests;

    #[test_only]
    friend ethos::leaderboard_2048_tests;

    const DEFAULT_FEE: u64 = 300_000_000;

    const EInvalidPlayer: u64 = 0;
    const ENotMaintainer: u64 = 1;
    const ENoBalance: u64 = 2;

    /// One-Time-Witness for the module.
    struct GAME_2048 has drop {}

    struct Game2048 has key, store {
        id: UID,
        game: u64,
        player: address,
        active_board: GameBoard2048,
        move_count: u64,
        score: u64,
        top_tile: u64,      
        game_over: bool
    }

    struct GameMove2048 has store {
        direction: u64,
        player: address
    }

    struct Game2048Maintainer has key {
        id: UID,
        maintainer_address: address,
        game_count: u64,
        fee: u64,
        balance: Balance<SUI>
    }

    struct NewGameEvent2048 has copy, drop {
        game_id: ID,
        player: address,
        score: u64,
        packed_spaces: u64
    }

    struct GameMoveEvent2048 has copy, drop {
        game_id: ID,
        direction: u64,
        move_count: u64,
        packed_spaces: u64,
        last_tile: vector<u64>,
        top_tile: u64,
        score: u64,
        game_over: bool
    }

    struct GameOverEvent2048 has copy, drop {
        game_id: ID,
        top_tile: u64,
        score: u64
    }

    fun init(otw: GAME_2048, ctx: &mut TxContext) {
        let keys = vector[
            utf8(b"name"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
            utf8(b"project_name"),
            utf8(b"project_image_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"Sui 2048"),
            utf8(b"https://raw.githubusercontent.com/s2048/sui2048/main/images/{top_tile}.png"),
            utf8(b"Sui 2048 is a 100% on-chain game. Play to airdrop!"),
            utf8(b"https://s2048.xyz"),
            utf8(b"Sui 2048"),
            utf8(b"https://raw.githubusercontent.com/s2048/sui2048/main/logo/projects2048.png"),
            utf8(b"SUI2048")
        ];

        let publisher = package::claim(otw, ctx);

        let display = display::new_with_fields<Game2048>(
            &publisher, keys, values, ctx
        );

        display::update_version(&mut display);

        let maintainer = create_maintainer(ctx);

        public_transfer(publisher, sender(ctx));
        public_transfer(display, sender(ctx));
        transfer::share_object(maintainer);
    }

    // PUBLIC ENTRY FUNCTIONS //
    
    public entry fun create(maintainer: &mut Game2048Maintainer, fee: vector<Coin<SUI>>, ctx: &mut TxContext) {
        let (paid, remainder) = merge_and_split(fee, maintainer.fee, ctx);

        coin::put(&mut maintainer.balance, paid);
        transfer::public_transfer(remainder, tx_context::sender(ctx));

        let player = tx_context::sender(ctx);
        let uid = object::new(ctx);
        let random = object::uid_to_bytes(&uid);
        let initial_game_board = game_board_2048::default(random);

        let score = *game_board_2048::score(&initial_game_board);
        let top_tile = *game_board_2048::top_tile(&initial_game_board);

        let game = Game2048 {
            id: uid,
            game: maintainer.game_count + 1,
            player,
            move_count: 0,
            score,
            top_tile,
            active_board: initial_game_board,
            game_over: false,
        };

        event::emit(NewGameEvent2048 {
            game_id: object::uid_to_inner(&game.id),
            player,
            score,
            packed_spaces: *game_board_2048::packed_spaces(&initial_game_board)
        });
        
        maintainer.game_count = maintainer.game_count + 1;

        transfer(game, player);
    }

    public entry fun make_move(game: &mut Game2048, direction: u64, ctx: &mut TxContext)  {
        let new_board;
        {
            new_board = *&game.active_board;

            let uid = object::new(ctx);
            let random = object::uid_to_bytes(&uid);
            object::delete(uid);
            game_board_2048::move_direction(&mut new_board, direction, random);
        };

        let move_count = game.move_count + 1;
        let top_tile = *game_board_2048::top_tile(&new_board);
        let score = *game_board_2048::score(&new_board);
        let game_over = *game_board_2048::game_over(&new_board);

        event::emit(GameMoveEvent2048 {
            game_id: object::uid_to_inner(&game.id),
            direction: direction,
            move_count,
            packed_spaces: *game_board_2048::packed_spaces(&new_board),
            last_tile: *game_board_2048::last_tile(&new_board),
            top_tile,
            score,
            game_over
        });

        if (game_over) {            
            event::emit(GameOverEvent2048 {
                game_id: object::uid_to_inner(&game.id),
                top_tile,
                score
            });
        };

        game.move_count = move_count;
        game.active_board = new_board;
        game.score = score;
        game.top_tile = top_tile;
        game.game_over = game_over;
    }

    public entry fun pay_maintainer(maintainer: &mut Game2048Maintainer, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == maintainer.maintainer_address, ENotMaintainer);
        let amount = balance::value<SUI>(&maintainer.balance);
        assert!(amount > 0, ENoBalance);
        let payment = coin::take(&mut maintainer.balance, amount, ctx);
        transfer::public_transfer(payment, tx_context::sender(ctx));
    }

    public entry fun change_maintainer(maintainer: &mut Game2048Maintainer, new_maintainer: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == maintainer.maintainer_address, ENotMaintainer);
        maintainer.maintainer_address = new_maintainer;
    }

    public entry fun change_fee(maintainer: &mut Game2048Maintainer, new_fee: u64, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == maintainer.maintainer_address, ENotMaintainer);
        maintainer.fee = new_fee;
    }
 
    // PUBLIC ACCESSOR FUNCTIONS //

    public fun id(game: &Game2048): ID {
        object::uid_to_inner(&game.id)
    }

    public fun player(game: &Game2048): &address {
        &game.player
    }

    public fun active_board(game: &Game2048): &GameBoard2048 {
        &game.active_board
    }

    public fun top_tile(game: &Game2048): &u64 {
        let game_board = active_board(game);
        game_board_2048::top_tile(game_board)
    }

    public fun score(game: &Game2048): &u64 {
        let game_board = active_board(game);
        game_board_2048::score(game_board)
    }

    public fun move_count(game: &Game2048): &u64 {
        &game.move_count
    }

    // Friend functions

    public(friend) fun create_maintainer(ctx: &mut TxContext): Game2048Maintainer {
        Game2048Maintainer {
            id: object::new(ctx),
            maintainer_address: sender(ctx),
            game_count: 0,
            fee: DEFAULT_FEE,
            balance: balance::zero<SUI>()
        }
    }

    fun merge_and_split(
        coins: vector<Coin<SUI>>, amount: u64, ctx: &mut TxContext
    ): (Coin<SUI>, Coin<SUI>) {
        let base = vector::pop_back(&mut coins);
        pay::join_vec(&mut base, coins);
        let coin_value = coin::value(&base);
        assert!(coin_value >= amount, coin_value);
        (coin::split(&mut base, amount, ctx), base)
    }
}