use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anki::backend::{init_backend, Backend};
use anki_proto::backend::BackendInit;
use anki_proto::collection::OpenCollectionRequest;
use anki_proto::decks::{DeckId, DeckTreeNode, DeckTreeRequest};
use anki_proto::import_export::{
    ImportAnkiPackageOptions, ImportAnkiPackageRequest, ImportResponse,
};
use anki_proto::scheduler::{GetQueuedCardsRequest, QueuedCards};
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

fn temp_collection(label: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!("said-{label}-{nonce}"))
}

fn flatten<'a>(node: &'a DeckTreeNode, output: &mut Vec<&'a DeckTreeNode>) {
    for child in &node.children {
        output.push(child);
        flatten(child, output);
    }
}

fn verify_package(package: &Path, expected_name: &str) {
    let root = temp_collection(expected_name);
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

    let _: anki_proto::generic::Empty = call(
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

    let imported: ImportResponse = call(
        &backend,
        37,
        2,
        ImportAnkiPackageRequest {
            package_path: package.to_string_lossy().into(),
            options: Some(ImportAnkiPackageOptions {
                merge_notetypes: true,
                with_scheduling: true,
                with_deck_configs: true,
                ..Default::default()
            }),
        },
    );
    assert!(
        !imported.log.unwrap_or_default().new.is_empty(),
        "{expected_name} imported no notes"
    );

    let tree: DeckTreeNode = call(
        &backend,
        7,
        4,
        DeckTreeRequest {
            now: 1_800_000_000,
        },
    );
    let mut decks = Vec::new();
    flatten(&tree, &mut decks);
    let target = decks
        .iter()
        .find(|deck| deck.name.contains(expected_name))
        .expect("expected deck missing");

    let _: anki_proto::collection::OpChanges = call(
        &backend,
        7,
        22,
        DeckId { did: target.deck_id },
    );
    let queue: QueuedCards = call(
        &backend,
        13,
        3,
        GetQueuedCardsRequest {
            fetch_limit: 1,
            intraday_learning_only: false,
        },
    );
    assert!(!queue.cards.is_empty(), "{expected_name} has no review card");

    fs::remove_dir_all(root).ok();
}

#[test]
fn imports_and_queues_said_target_packages() {
    let speaking = std::env::var_os("SAID_SPEAKING_APKG")
        .expect("SAID_SPEAKING_APKG is required");
    let pronounce = std::env::var_os("SAID_PRONOUNCE_APKG")
        .expect("SAID_PRONOUNCE_APKG is required");
    verify_package(Path::new(&speaking), "English_Speaking");
    verify_package(Path::new(&pronounce), "Pronounce_Learning");
}
