import XCTest
import Cuckoo
import RxSwift
@testable import Bank_Dev_T

class SendInteractorTests: XCTestCase {
    enum StubError: Error { case some }

    private var mockDelegate: MockISendInteractorDelegate!
    private var mockCurrencyManager: MockICurrencyManager!
    private var mockRateStorage: MockIRateStorage!
    private var mockLocalStorage: MockILocalStorage!
    private var mockPasteboardManager: MockIPasteboardManager!

    private let coinCode = "BTC"
    private let baseCurrency = Currency(code: "USD", symbol: "$")
    private let balance = 123.45

    private var mockAdapter: MockIAdapter!
    private var wallet: Wallet!
    private var interactorState: SendInteractorState!
    private var input = SendUserInput()

    private var interactor: SendInteractor!

    override func setUp() {
        super.setUp()

        mockAdapter = MockIAdapter()
        wallet = Wallet(title: "some", coinCode: coinCode, adapter: mockAdapter)
        interactorState = SendInteractorState(wallet: wallet)

        mockDelegate = MockISendInteractorDelegate()
        mockCurrencyManager = MockICurrencyManager()
        mockRateStorage = MockIRateStorage()
        mockLocalStorage = MockILocalStorage()
        mockPasteboardManager = MockIPasteboardManager()

        stub(mockDelegate) { mock in
            when(mock.didUpdateRate()).thenDoNothing()
        }
        stub(mockCurrencyManager) { mock in
            when(mock.baseCurrency.get).thenReturn(baseCurrency)
        }
        stub(mockAdapter) { mock in
            when(mock.balance.get).thenReturn(balance)
            when(mock.validate(address: any())).thenDoNothing()
            when(mock.fee(for: any(), address: any(), senderPay: any())).thenReturn(0)
        }
        stub(mockPasteboardManager) { mock in
            when(mock.set(value: any())).thenDoNothing()
        }

        interactor = SendInteractor(currencyManager: mockCurrencyManager, rateStorage: mockRateStorage, localStorage: mockLocalStorage, pasteboardManager: mockPasteboardManager, state: interactorState)
        interactor.delegate = mockDelegate
    }

    override func tearDown() {
        mockDelegate = nil
        mockCurrencyManager = nil
        mockRateStorage = nil
        mockLocalStorage = nil
        mockPasteboardManager = nil

        mockAdapter = nil
        wallet = nil
        interactorState = nil

        interactor = nil

        super.tearDown()
    }

    func testAddressFromPasteboard() {
        let address = "address"

        stub(mockPasteboardManager) { mock in
            when(mock.value.get).thenReturn(address)
        }

        XCTAssertEqual(interactor.addressFromPasteboard, address)
    }

    func testConvertedAmount_FromCoinToCurrency() {
        let rateValue = 987.65
        let amount = 123.45

        interactorState.rateValue = rateValue

        XCTAssertEqual(interactor.convertedAmount(forInputType: .coin, amount: amount), amount * rateValue)
    }

    func testConvertedAmount_FromCurrencyToCoin() {
        let rateValue = 987.65
        let amount = 123.45

        interactorState.rateValue = rateValue

        XCTAssertEqual(interactor.convertedAmount(forInputType: .currency, amount: amount), amount / rateValue)
    }

    func testConvertedAmount_NoRate() {
        XCTAssertEqual(interactor.convertedAmount(forInputType: .coin, amount: 123.45), nil)
    }

    func testState_InputType_Coin() {
        input.inputType = .coin

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.inputType, SendInputType.coin)
    }

    func testState_InputType_Currency() {
        input.inputType = .currency

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.inputType, SendInputType.currency)
    }

    func testState_CoinValue_CoinType() {
        let amount = 123.45

        input.inputType = .coin
        input.amount = amount

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.coinValue, CoinValue(coinCode: coinCode, value: amount))
    }

    func testState_CoinValue_CurrencyType() {
        let rateValue = 987.65
        let amount = 123.45

        interactorState.rateValue = rateValue
        input.inputType = .currency
        input.amount = amount

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.coinValue, CoinValue(coinCode: coinCode, value: amount / rateValue))
    }

    func testState_CoinValue_CurrencyType_NoRate() {
        input.inputType = .currency

        let state = interactor.state(forUserInput: input)

        XCTAssertNil(state.coinValue)
    }

    func testState_CurrencyValue_CoinType() {
        let rateValue = 987.65
        let amount = 123.45

        interactorState.rateValue = rateValue
        input.inputType = .coin
        input.amount = amount

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.currencyValue, CurrencyValue(currency: baseCurrency, value: amount * rateValue))
    }

    func testState_CurrencyValue_CurrencyType() {
        let amount = 123.45

        input.inputType = .currency
        input.amount = amount

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.currencyValue, CurrencyValue(currency: baseCurrency, value: amount))
    }

    func testState_CurrencyValue_CoinType_NoRate() {
        input.inputType = .coin

        let state = interactor.state(forUserInput: input)

        XCTAssertNil(state.currencyValue)
    }

    func testState_AmountError_CoinType_EnoughBalance() {
        input.inputType = .coin
        input.amount = balance - 1

        let state = interactor.state(forUserInput: input)

        XCTAssertNil(state.amountError)
    }

    func testState_AmountError_CoinType_InsufficientBalance() {
        let address = "address"
        input.inputType = .coin
        input.amount = balance + 1
        input.address = address

        let fee: Double = 0.00000123
        let expectedAvailableBalance: Double = 123.45 - fee

        stub(mockAdapter) { mock in
            when(mock.fee(for: equal(to: input.amount), address: equal(to: address), senderPay: true)).thenThrow(FeeError.insufficientAmount(fee: fee))
        }

        let state = interactor.state(forUserInput: input)

        let expectedAmountError = AmountError.insufficientAmount(
                amountInfo: .coinValue(coinValue: CoinValue(coinCode: coinCode, value: expectedAvailableBalance))
        )
        XCTAssertEqual(state.amountError, expectedAmountError)
    }

    func testState_AmountError_CurrencyType_EnoughBalance() {
        let rateValue = 987.65
        let currencyBalance = balance * rateValue

        interactorState.rateValue = rateValue
        input.inputType = .currency
        input.amount = currencyBalance - 1

        let state = interactor.state(forUserInput: input)

        XCTAssertNil(state.amountError)
    }

    func testState_AmountError_CurrencyType_InsufficientBalance() {
        let rateValue = 987.65
        let currencyBalance = balance * rateValue
        let address = "address"

        interactorState.rateValue = rateValue
        input.inputType = .currency
        input.amount = currencyBalance + 1
        input.address = address

        let fee: Double = 0.00000123

        stub(mockAdapter) { mock in
            when(mock.fee(for: any(), address: any(), senderPay: any())).thenThrow(FeeError.insufficientAmount(fee: fee))//any, because 123.45 * 6543.21 / 6543.21 = 123.4501528301858
        }

        let state = interactor.state(forUserInput: input)

        let expectedCurrencyAvailableBalance: Double = (123.45 - fee) * rateValue
        let expectedAmountError = AmountError.insufficientAmount(
                amountInfo: .currencyValue(currencyValue: CurrencyValue(currency: baseCurrency, value: expectedCurrencyAvailableBalance))
        )
        XCTAssertEqual(state.amountError, expectedAmountError)
    }

    func testState_Address() {
        let address = "address"
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.address, address)
    }

    func testState_AddressError_Valid() {
        let state = interactor.state(forUserInput: input)

        XCTAssertNil(state.addressError)
    }

    func testState_AddressError_Invalid() {
        let address = "address"
        input.address = address

        stub(mockAdapter) { mock in
            when(mock.validate(address: equal(to: address))).thenThrow(StubError.some)
        }

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.addressError, AddressError.invalidAddress)
    }

    func testState_FeeCoinValue_CoinType() {
        let fee = 0.123
        let amount = 123.45
        let address = "address"

        stub(mockAdapter) { mock in
            when(mock.fee(for: amount, address: equal(to: address), senderPay: true)).thenReturn(fee)
        }

        input.inputType = .coin
        input.amount = amount
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.feeCoinValue, CoinValue(coinCode: coinCode, value: fee))
    }

    func testState_FeeCoinValue_CurrencyType() {
        let rateValue = 987.65
        let fee = 0.123
        let amount = 123.45
        let address = "address"
        let coinAmount = amount / rateValue

        stub(mockAdapter) { mock in
            when(mock.fee(for: coinAmount, address: equal(to: address), senderPay: true)).thenReturn(fee)
        }

        interactorState.rateValue = rateValue
        input.inputType = .currency
        input.amount = amount
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.feeCoinValue, CoinValue(coinCode: coinCode, value: fee))
    }

    func testState_FeeCurrencyValue_CoinType() {
        let rateValue = 987.65
        let fee = 0.123
        let amount = 123.45
        let address = "address"

        stub(mockAdapter) { mock in
            when(mock.fee(for: amount, address: equal(to: address), senderPay: true)).thenReturn(fee)
        }

        interactorState.rateValue = rateValue
        input.inputType = .coin
        input.amount = amount
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.feeCurrencyValue, CurrencyValue(currency: baseCurrency, value: fee * rateValue))
    }

    func testState_FeeCurrencyValue_CoinType_InsufficientBalance() {
        let rateValue = 987.65
        let fee = 0.123
        let amount = 123.45
        let address = "address"

        stub(mockAdapter) { mock in
            when(mock.fee(for: equal(to: amount), address: equal(to: address), senderPay: true)).thenThrow(FeeError.insufficientAmount(fee: fee))
        }

        interactorState.rateValue = rateValue
        input.inputType = .coin
        input.amount = amount
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.feeCurrencyValue, CurrencyValue(currency: baseCurrency, value: fee * rateValue))
    }

    func testState_FeeCurrencyValue_CurrencyType() {
        let rateValue = 987.65
        let fee = 0.123
        let amount = 123.45
        let address = "address"
        let coinAmount = amount / rateValue

        stub(mockAdapter) { mock in
            when(mock.fee(for: coinAmount, address: equal(to: address), senderPay: true)).thenReturn(fee)
        }

        interactorState.rateValue = rateValue
        input.inputType = .currency
        input.amount = amount
        input.address = address

        let state = interactor.state(forUserInput: input)

        XCTAssertEqual(state.feeCurrencyValue, CurrencyValue(currency: baseCurrency, value: fee * rateValue))
    }

    func testCopyAddress() {
        let address = "some_address"

        interactor.copy(address: address)

        verify(mockPasteboardManager).set(value: equal(to: address))
    }

    func testFetchRate() {
        let rateValue = 987.65

        stub(mockRateStorage) { mock in
            when(mock.nonExpiredLatestRateValueObservable(forCoinCode: equal(to: coinCode), currencyCode: equal(to: baseCurrency.code))).thenReturn(Observable.just(rateValue))
        }

        interactor.fetchRate()

        XCTAssertEqual(interactorState.rateValue, rateValue)
        verify(mockDelegate).didUpdateRate()
    }

    func testDefaultInputType() {
        let inputType = SendInputType.currency

        stub(mockLocalStorage) { mock in
            when(mock.sendInputType.get).thenReturn(inputType)
        }

        XCTAssertEqual(interactor.defaultInputType, inputType)
    }

    func testDefaultInputType_noValueInLocalStorage() {
        stub(mockLocalStorage) { mock in
            when(mock.sendInputType.get).thenReturn(nil)
        }

        XCTAssertEqual(interactor.defaultInputType, SendInputType.coin)
    }

    func testSetInputType() {
        let inputType = SendInputType.currency

        stub(mockLocalStorage) { mock in
            when(mock.sendInputType.set(any())).thenDoNothing()
        }

        interactor.set(inputType: inputType)

        verify(mockLocalStorage).sendInputType.set(equal(to: inputType))
    }

}
