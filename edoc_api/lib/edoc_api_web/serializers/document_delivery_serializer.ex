defmodule EdocApiWeb.Serializers.DocumentDeliverySerializer do
  def to_map(delivery) do
    %{
      id: delivery.id,
      channel: delivery.channel,
      kind: delivery.kind,
      status: delivery.status,
      recipient_email: delivery.recipient_email,
      recipient_phone: delivery.recipient_phone,
      recipient_name: delivery.recipient_name,
      sent_at: delivery.sent_at,
      opened_at: delivery.opened_at,
      inserted_at: delivery.inserted_at,
      updated_at: delivery.updated_at
    }
  end
end
