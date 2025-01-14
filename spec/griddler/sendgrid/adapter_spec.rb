require 'spec_helper'

describe Griddler::Sendgrid::Adapter do
  it 'registers itself with griddler' do
    Griddler.adapter_registry[:sendgrid].should eq Griddler::Sendgrid::Adapter
  end
end

describe Griddler::Sendgrid::Adapter, '.normalize_params' do
  it_should_behave_like 'Griddler adapter',
    :sendgrid,
    {
      text: 'hi',
      to: 'Hello World <hi@example.com>',
      cc: 'emily@example.com',
      from: 'There <there@example.com>',
      charsets: { to: 'UTF-8', text: 'iso-8859-1' }.to_json
    }

  it 'changes attachments to an array of files' do
    params = default_params.merge(
      attachments: '2',
      attachment1: upload_1,
      attachment2: upload_2,
     'attachment-info' => <<-eojson
        {
          "attachment2": {
            "filename": "photo2.jpg",
            "name": "photo2.jpg",
            "type": "image/jpeg"
          },
          "attachment1": {
            "filename": "photo1.jpg",
            "name": "photo1.jpg",
            "type": "image/jpeg"
          }
        }
      eojson
    )

    normalized_params = normalize_params(params)
    normalized_params[:attachments].should eq [upload_1, upload_2]
    normalized_params.should_not have_key(:attachment1)
    normalized_params.should_not have_key(:attachment2)
    normalized_params.should_not have_key(:attachment_info)
  end

  it "uses sendgrid attachment info for filename" do
    params = default_params.merge(
      attachments: "2",
      attachment1: upload_1,
      attachment2: upload_2,
      "attachment-info" => <<-eojson
        {
          "attachment2": {
            "filename": "sendgrid-filename2.jpg",
            "name": "photo2.jpg",
            "type": "image/jpeg"
          },
          "attachment1": {
            "filename": "sendgrid-filename1.jpg",
            "name": "photo1.jpg",
            "type": "image/jpeg"
          }
        }
      eojson
    )

    attachments = normalize_params(params)[:attachments]

    attachments.first.original_filename.should eq "sendgrid-filename1.jpg"
    attachments.second.original_filename.should eq "sendgrid-filename2.jpg"
  end

  it 'has no attachments' do
    params = default_params.merge(attachments: '0')

    normalized_params = normalize_params(params)
    normalized_params[:attachments].should be_empty
  end

  it 'splits to into an array' do
    normalized_params = normalize_params(default_params)

    normalized_params[:to].should eq [
      '"Mr Fugushima at Fugu, Inc" <hi@example.com>',
      'Foo bar <foo@example.com>',
      '"Eichhörnchen" <squirrel@example.com>',
      'no-name@example.com',
    ]
  end

  it 'wraps cc in an array' do
    normalized_params = normalize_params(default_params)

    normalized_params[:cc].should eq [default_params[:cc]]
  end

  it 'returns an array even if cc is empty' do
    params = default_params.merge(cc: nil)
    normalized_params = normalize_params(params)

    normalized_params[:cc].should eq []
  end

  it 'returns an array even if bcc is an empty string' do
    params = default_params.merge(envelope: '')
    normalized_params = normalize_params(params)

    normalized_params[:bcc].should eq []
  end

  it 'wraps bcc in an array' do
    normalized_params = normalize_params(default_params)

    normalized_params[:bcc].should eq ["johny@example.com"]
  end

  it 'returns an array even if bcc is empty' do
    params = default_params.merge(envelope: nil)
    normalized_params = normalize_params(params)

    normalized_params[:bcc].should eq []
  end

  it 'returns an empty array when the envelope to is the same as the base to' do
    params = default_params.merge(envelope: "{\"to\":[\"hi@example.com\"]}")
    normalized_params = normalize_params(params)

    normalized_params[:bcc].should eq []
  end

  it 'returns the charsets as a hash' do
    normalized_params = normalize_params(default_params)
    charsets = normalized_params[:charsets]

    charsets.should be_present
    charsets[:text].should eq 'UTF-8'
    charsets[:to].should eq 'UTF-8'
  end

  it 'does not explode if charsets is not JSON-able' do
    params = default_params.merge(charsets: 'This is not JSON')

    normalize_params(params)[:charsets].should eq({})
  end

  it 'does not explode if address is not parseable' do
    params = default_params.merge(cc: '"Closing Bracket Missing For Some Reason" <hi@example.com')

    normalize_params(params)[:cc].should eq([])
  end

  it 'defaults charsets to an empty hash if it is not specified in params' do
    params = default_params.except(:charsets)
    normalize_params(params)[:charsets].should eq({})
  end

  it 'normalizes the spam report into a griddler friendly format' do
    normalized_params = normalize_params(default_params)

    normalized_params[:spam_report].should eq({
      score: '1.234',
      report: 'Some spam report',
    })
  end

  it 'parses sendgrid filename correctly' do
    params = default_params.merge(
      attachments: "2",
      attachment1: upload_1,
      attachment2: upload_2,
      "attachment-info" => <<-eojson
        {
          "attachment2": {
            "filename": "\xc3\x28.jpg",
            "name": "photo2.jpg",
            "type": "image/jpeg"
          },
          "attachment1": {
            "filename": "sendgrid-filename1.jpg",
            "name": "photo1.jpg",
            "type": "image/jpeg"
          }
        }
      eojson
    )

    attachments = normalize_params(params)[:attachments]

    attachments.first.original_filename.should eq "sendgrid-filename1.jpg"
    attachments.second.original_filename.should eq "Ã(.jpg"
  end

  it 'parses envelope correctly' do
    params = default_params.merge(
      envelope: "{\"to\":[\"\xc3\x28 <johny@example.com>\"], \"from\": [\"there@example.com\"]}",
    )

    normalize_params(params)[:bcc].should eq ["Ã( <johny@example.com>"]
  end

  it 'converts subject to utf-8' do
    params = default_params.merge(
      subject: "\xc3\x28".force_encoding(Encoding::ISO_8859_1)
    )

    subject = normalize_params(params)[:subject]
    subject.encoding.should eq Encoding::UTF_8
    subject.should eq "Ã("
  end

  it 'converts html to utf-8' do
    params = default_params.merge(
      html: "\xc3\x28<p>text</p>".force_encoding(Encoding::ISO_8859_1)
    )

    html = normalize_params(params)[:html]
    html.encoding.should eq Encoding::UTF_8
    html.should eq "Ã(<p>text</p>"
  end

  it 'converts text to utf-8' do
    params = default_params.merge(
      text: "\xc3\x28".force_encoding(Encoding::ISO_8859_1)
    )

    text = normalize_params(params)[:text]
    text.encoding.should eq Encoding::UTF_8
    text.should eq "Ã("
  end

  def default_params
    {
      text: 'hi',
      to: '"Mr Fugushima at Fugu, Inc" <hi@example.com>, Foo bar <foo@example.com>, Eichhörnchen <squirrel@example.com>, <no-name@example.com>',
      cc: 'cc@example.com',
      from: 'there@example.com',
      envelope: "{\"to\":[\"johny@example.com\"], \"from\": [\"there@example.com\"]}",
      charsets: { to: 'UTF-8', text: 'iso-8859-1' }.to_json,
      spam_score: '1.234',
      spam_report: 'Some spam report'
    }
  end
end
