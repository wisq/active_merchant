require 'test_helper'

class SagePayTest < Test::Unit::TestCase
  def setup
    @gateway = SagePayGateway.new(
      :login => 'X'
    )

    @credit_card = credit_card('4242424242424242', :type => 'visa')
    @options = { 
      :billing_address => { 
        :name => 'Tekin Suleyman',
        :address1 => 'Flat 10 Lapwing Court',
        :address2 => 'West Didsbury',
        :city => "Manchester",
        :county => 'Greater Manchester',
        :country => 'GB',
        :zip => 'M20 2PS'
      },
      :order_id => '1',
      :description => 'Store purchase',
      :ip => '86.150.65.37',
      :email => 'tekin@tekin.co.uk',
      :phone => '0161 123 4567'
    }
    @amount = 100
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_equal "1;B8AE1CF6-9DEF-C876-1BB4-9B382E6CE520;4193753;OHMETD7DFK;purchase", response.authorization
    assert_success response
  end

  def test_unsuccessful_purchase
    @gateway.expects(:ssl_post).returns(unsuccessful_purchase_response)
    
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_failure response
  end

  def test_supports_buyer_authentication
    assert @gateway.supports_buyer_authentication
  end
  
  def test_buyer_authentication
    @gateway.stubs(:ssl_post).twice.returns(buyer_auth_response, successful_purchase_response)
    
    response = @gateway.begin_buyer_authentication(100, @credit_card, @options)
    assert_failure response
    assert response.buyer_auth?
    
    assert_equal 'BSkaFwYFFTYAGyFbEAcBFhwVEEkvLCMcGgBRUnZaTGFWc087NTFVKgAANS0KADoZCCAMBnIeOx', response.pa_req
    assert_equal '069254975634711089', response.md
    assert_equal 'https://test.sagepay.com/Simulator/3DAuthPage.asp', response.acs_url
    
    response = @gateway.complete_buyer_authentication('PaRes' => 'PARes VALUE', 'MD' => 'MD VALUE')
    assert_success response
  end
  
  def test_purchase_url
    assert_equal 'https://test.sagepay.com/gateway/service/vspdirect-register.vsp', @gateway.send(:url_for, :purchase)
  end
  
  def test_capture_url
    assert_equal 'https://test.sagepay.com/gateway/service/release.vsp', @gateway.send(:url_for, :capture)
  end
  
  def test_electron_cards
    # Visa range
    assert_no_match SagePayGateway::ELECTRON, '4245180000000000'
    
    # First electron range
    assert_match SagePayGateway::ELECTRON, '4245190000000000'
                                                                
    # Second range                                              
    assert_match SagePayGateway::ELECTRON, '4249620000000000'
    assert_match SagePayGateway::ELECTRON, '4249630000000000'
                                                                
    # Third                                                     
    assert_match SagePayGateway::ELECTRON, '4508750000000000'
                                                                
    # Fourth                                                    
    assert_match SagePayGateway::ELECTRON, '4844060000000000'
    assert_match SagePayGateway::ELECTRON, '4844080000000000'
                                                                
    # Fifth                                                     
    assert_match SagePayGateway::ELECTRON, '4844110000000000'
    assert_match SagePayGateway::ELECTRON, '4844550000000000'
                                                                
    # Sixth                                                     
    assert_match SagePayGateway::ELECTRON, '4917300000000000'
    assert_match SagePayGateway::ELECTRON, '4917590000000000'
                                                                
    # Seventh                                                   
    assert_match SagePayGateway::ELECTRON, '4918800000000000'
    
    # Visa
    assert_no_match SagePayGateway::ELECTRON, '4918810000000000'
    
    # 19 PAN length
    assert_match SagePayGateway::ELECTRON, '4249620000000000000'
    
    # 20 PAN length
    assert_no_match SagePayGateway::ELECTRON, '42496200000000000'
  end
  
  def test_avs_result
     @gateway.expects(:ssl_post).returns(successful_purchase_response)

     response = @gateway.purchase(@amount, @credit_card, @options)
     assert_equal 'Y', response.avs_result['postal_match']
     assert_equal 'N', response.avs_result['street_match']
   end

   def test_cvv_result
     @gateway.expects(:ssl_post).returns(successful_purchase_response)

     response = @gateway.purchase(@amount, @credit_card, @options)
     assert_equal 'N', response.cvv_result['code']
   end

  def test_dont_send_fractional_amount_for_chinese_yen
    @amount = 100_00  # 100 YEN
    @options[:currency] = 'JPY'

    @gateway.expects(:add_pair).with({}, :Amount, '100', :required => true)
    @gateway.expects(:add_pair).with({}, :Currency, 'JPY', :required => true)

    @gateway.send(:add_amount, {}, @amount, @options)
  end

  def test_send_fractional_amount_for_british_pounds
    @gateway.expects(:add_pair).with({}, :Amount, '1.00', :required => true)
    @gateway.expects(:add_pair).with({}, :Currency, 'GBP', :required => true)

    @gateway.send(:add_amount, {}, @amount, @options)
  end
   
  private

  def successful_purchase_response
    <<-RESP
VPSProtocol=2.23
Status=OK
StatusDetail=0000 : The Authorisation was Successful.
VPSTxId=B8AE1CF6-9DEF-C876-1BB4-9B382E6CE520
SecurityKey=OHMETD7DFK
TxAuthNo=4193753
AVSCV2=NO DATA MATCHES
AddressResult=NOTMATCHED
PostCodeResult=MATCHED
CV2Result=NOTMATCHED
3DSecureStatus=NOTCHECKED
    RESP
  end
  
  def unsuccessful_purchase_response
    <<-RESP
VPSProtocol=2.23
Status=NOTAUTHED
StatusDetail=Direct 3D-Secure transaction from Simulator.
VPSTxId={63FA577C-3A5E-4D02-A3C5-516EC3149F29}
SecurityKey=IR1CD2KKGT
AVSCV2=ADDRESS MATCH ONLY
AddressResult=MATCHED
PostCodeResult=MATCHED
CV2Result=NOTCHECKED
3DSecureStatus=NOTAUTHED
    RESP
  end

  def buyer_auth_response
    <<-RESP
VPSProtocol=2.23
Status=3DAUTH
3DSecureStatus=OK
MD=069254975634711089
ACSURL=https://test.sagepay.com/Simulator/3DAuthPage.asp
PAReq=BSkaFwYFFTYAGyFbEAcBFhwVEEkvLCMcGgBRUnZaTGFWc087NTFVKgAANS0KADoZCCAMBnIeOx
cWRg0LERdOOTQRDFRcVXJbUgwTMBsBCxABJw4DJHE+ERgPCi8MVC0HIAROCAAfBUk4ER89DD0IWDlfMH
ZUclwvIlhKLV5ebHgvNkxBJ3tdMmJScCtXVkREXlcvBQoUUicYBDYcB3IiBikrNCc2LQ==
    RESP
  end
end
