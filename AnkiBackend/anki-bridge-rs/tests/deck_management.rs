use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use anki::backend::{init_backend, Backend};
use anki_proto::backend::BackendInit;
use anki_proto::collection::{
    OpenCollectionRequest, OpChanges, OpChangesWithCount, OpChangesWithId,
};
use anki_proto::decks::{
    Deck, DeckId, DeckIds, DeckTreeNode, DeckTreeRequest, RenameDeckRequest,
    ReparentDecksRequest,
};
use anki_proto::generic::Empty;
use anki_proto::notes::{AddNoteRequest, AddNoteResponse, Note};
use anki_proto::notetypes::{NotetypeId, NotetypeNames};
use anki_proto::scheduler::custom_study_request::Value as CustomStudyValue;
use anki_proto::scheduler::{
    CustomStudyDefaultsRequest, CustomStudyDefaultsResponse, CustomStudyRequest,
    ExtendLimitsRequest,
};
use prost::Message;

fn call<Req: Message, Resp: Message + Default>(
    backend: &Backend,
    service: u32,
    method: u32,
    request: Req,
) -> Resp {
    let output = backend
        .run_service_method(service, method, &request.encode_to_vec())
        .expect("rslib method failed");
    Resp::decode(output.as_slice()).expect("invalid rslib response")
}

fn temp_collection() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!("said-deck-management-{nonce}"))
}

fn add_deck(backend: &Backend, name: &str) -> i64 {
    let mut deck: Deck = call(backend, 7, 0, Empty {});
    deck.name = name.into();
    let added: OpChangesWithId = call(backend, 7, 1, deck);
    added.id
}

fn flatten<'a>(node: &'a DeckTreeNode, output: &mut Vec<&'a DeckTreeNode>) {
    for child in &node.children {
        output.push(child);
        flatten(child, output);
    }
}

#[test]
fn deck_crud_hierarchy_and_recursive_card_deletion() {
    let root = temp_collection();
    let media = root.join("collection.media");
    fs::create_dir_all(&media).unwrap();

    let backend = init_backend(
        &BackendInit {
            preferred_langs: vec!["en".into()],
            server: false,
            ..Default::default()
        }
        .encode_to_vec(),
    )
    .unwrap();

    let _: Empty = call(
        &backend,
        3,
        0,
        OpenCollectionRequest {
            collection_path: root.join("collection.anki2").to_string_lossy().into(),
            media_folder_path: media.to_string_lossy().into(),
            media_db_path: root.join("collection.media.db2").to_string_lossy().into(),
            ..Default::default()
        },
    );

    let parent_id = add_deck(&backend, "Parent");
    let child_id = add_deck(&backend, "Loose Child");
    let reparented: OpChangesWithCount = call(
        &backend,
        7,
        17,
        ReparentDecksRequest {
            deck_ids: vec![child_id],
            new_parent: parent_id,
        },
    );
    assert_eq!(reparented.count, 1);

    let _: OpChanges = call(
        &backend,
        7,
        18,
        RenameDeckRequest {
            deck_id: parent_id,
            new_name: "Renamed Parent".into(),
        },
    );
    let child: Deck = call(&backend, 7, 8, DeckId { did: child_id });
    assert_eq!(child.name, "Renamed Parent::Loose Child");

    let _: Empty = call(
        &backend,
        13,
        9,
        ExtendLimitsRequest {
            deck_id: child_id,
            new_delta: 1,
            review_delta: 1,
        },
    );
    let _: OpChanges = call(
        &backend,
        13,
        27,
        CustomStudyRequest {
            deck_id: child_id,
            value: Some(CustomStudyValue::NewLimitDelta(2)),
        },
    );
    let defaults: CustomStudyDefaultsResponse = call(
        &backend,
        13,
        28,
        CustomStudyDefaultsRequest { deck_id: child_id },
    );
    assert_eq!(defaults.extend_new, 2);

    let notetypes: NotetypeNames = call(&backend, 23, 8, Empty {});
    let notetype_id = notetypes
        .entries
        .iter()
        .find(|entry| entry.name == "Basic")
        .or_else(|| notetypes.entries.first())
        .expect("new collection should contain a stock notetype")
        .id;
    let mut note: Note = call(
        &backend,
        25,
        0,
        NotetypeId {
            ntid: notetype_id,
        },
    );
    note.fields = vec!["front".into(), "back".into()];
    let added: AddNoteResponse = call(
        &backend,
        25,
        1,
        AddNoteRequest {
            note: Some(note),
            deck_id: child_id,
        },
    );
    assert_ne!(added.note_id, 0);

    let deleted: OpChangesWithCount = call(
        &backend,
        7,
        16,
        DeckIds {
            dids: vec![parent_id],
        },
    );
    assert_eq!(deleted.count, 1, "removeDecks count is deleted cards");

    let tree: DeckTreeNode = call(&backend, 7, 4, DeckTreeRequest { now: 0 });
    let mut decks = Vec::new();
    flatten(&tree, &mut decks);
    assert!(!decks.iter().any(|deck| {
        deck.deck_id == parent_id || deck.deck_id == child_id
    }));

    fs::remove_dir_all(root).ok();
}
