use ironrdp_connector::{ClientConnector, ClientConnectorState, ConnectorErrorKind, Sequence as _};
use ironrdp_core::{WriteBuf, encode_vec};
use ironrdp_pdu::nego::{ConnectionConfirm, ResponseFlags, SecurityProtocol};
use ironrdp_pdu::x224::X224;

#[test]
fn server_selecting_standard_rdp_security_is_a_typed_mismatch() {
    let mut connector = ClientConnector::new(super::test_config(), "127.0.0.1:3389".parse().unwrap());
    connector.state = ClientConnectorState::ConnectionInitiationWaitConfirm {
        requested_protocol: SecurityProtocol::SSL,
    };

    let confirm = encode_vec(&X224(ConnectionConfirm::Response {
        flags: ResponseFlags::empty(),
        protocol: SecurityProtocol::empty(),
    }))
    .unwrap();

    let error = connector.step(&confirm, None, &mut WriteBuf::new()).unwrap_err();

    let ConnectorErrorKind::SecurityProtocolMismatch { requested, selected } = error.kind() else {
        panic!("expected a security protocol mismatch, got {error:?}");
    };
    assert_eq!(*requested, SecurityProtocol::SSL);
    assert!(selected.is_standard_rdp_security());
}
