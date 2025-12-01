def to_js(string, opts={})
  Ruby2JS.convert(string, opts.merge(filters: [])).to_s
end

describe 'literals' do
  it 'should parse integers' do
    to_js('1').must_equal '1'
    to_js('42').must_equal '42'
  end

  it 'should parse strings' do
    to_js('"hello"').must_equal '"hello"'
  end

  it 'should parse nil' do
    to_js('nil').must_equal 'null'
  end

  it 'should parse arrays' do
    to_js('[1, 2, 3]').must_equal '[1, 2, 3]'
  end
end
