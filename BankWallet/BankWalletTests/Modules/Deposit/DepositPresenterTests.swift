import XCTest
import RxSwift
import Cuckoo
@testable import Bank_Dev_T

class DepositPresenterTests: XCTestCase {
    private var mockRouter: MockIDepositRouter!
    private var mockInteractor: MockIDepositInteractor!
    private var mockView: MockIDepositView!

    private var presenter: DepositPresenter!

    private let bitcoin = "BTC"
    private let ether = "ETH"

    private let bitcoinTitle = "Bitcoin"
    private let etherTitle = "Ethereum"

    private let bitcoinAddress = "bitcoin_address"
    private let etherAddress = "ether_address"

    private var mockBitcoinAdapter: MockIAdapter!
    private var mockEtherAdapter: MockIAdapter!

    private var bitcoinWallet: Wallet!
    private var etherWallet: Wallet!

    override func setUp() {
        super.setUp()

        mockBitcoinAdapter = MockIAdapter()
        mockEtherAdapter = MockIAdapter()

        bitcoinWallet = Wallet(title: bitcoinTitle, coinCode: bitcoin, adapter: mockBitcoinAdapter)
        etherWallet = Wallet(title: etherTitle, coinCode: ether, adapter: mockEtherAdapter)

        mockRouter = MockIDepositRouter()
        mockInteractor = MockIDepositInteractor()
        mockView = MockIDepositView()

        stub(mockRouter) { mock in
            when(mock.share(address: any())).thenDoNothing()
        }
        stub(mockView) { mock in
            when(mock.showCopied()).thenDoNothing()
        }
        stub(mockInteractor) { mock in
            when(mock.wallets(forCoin: equal(to: nil))).thenReturn([bitcoinWallet, etherWallet])
            when(mock.copy(address: any())).thenDoNothing()
        }

        stub(mockBitcoinAdapter) { mock in
            when(mock.receiveAddress.get).thenReturn(bitcoinAddress)
        }
        stub(mockEtherAdapter) { mock in
            when(mock.receiveAddress.get).thenReturn(etherAddress)
        }

        presenter = DepositPresenter(interactor: mockInteractor, router: mockRouter)
        presenter.view = mockView
    }

    override func tearDown() {
        mockRouter = nil
        mockInteractor = nil
        mockView = nil

        presenter = nil

        super.tearDown()
    }

    func testGetAddressItems() {
        let expectedItems = [
            AddressItem(title: bitcoinTitle, address: bitcoinAddress, coinCode: bitcoin),
            AddressItem(title: etherTitle, address: etherAddress, coinCode: ether)
        ]

        XCTAssertEqual(presenter.addressItems(forCoin: nil), expectedItems)
    }

    func testOnCopy() {
        presenter.onCopy(addressItem: AddressItem(title: bitcoinTitle, address: bitcoinAddress, coinCode: bitcoin))

        verify(mockInteractor).copy(address: equal(to: bitcoinAddress))
        verify(mockView).showCopied()
    }

    func testOnShare() {
        presenter.onShare(addressItem: AddressItem(title: bitcoinTitle, address: bitcoinAddress, coinCode: bitcoin))

        verify(mockRouter).share(address: equal(to: bitcoinAddress))
    }

}
