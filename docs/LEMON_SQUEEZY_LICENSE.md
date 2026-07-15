# Lemon Squeezy License Setup

MoleCube uses Lemon Squeezy's public License API. The macOS app contains no Lemon Squeezy API key or webhook signing secret.

## Create the product

1. Create a one-time-purchase `MoleCube Pro` product and its selling variant in Lemon Squeezy.
2. Enable automatic license key generation for that variant.
3. Set the activation limit to the number of Macs included with a purchase, for example `2`.
4. Copy the Store ID, Product ID, Variant ID, and hosted checkout URL.

Lemon Squeezy emails the license key after payment. MoleCube then activates the key for the current Mac, validates it on launch, and releases the device activation when the customer removes the license in Settings.

## Configure the app

In the `MoleCubeMac` target's Info build settings, replace the placeholder values in both Debug and Release:

| Setting | Value |
| --- | --- |
| `LemonSqueezyStoreID` | Your numeric store ID |
| `LemonSqueezyProductID` | The MoleCube Pro product ID |
| `LemonSqueezyVariantID` | The purchasable variant ID |
| `LemonSqueezyCheckoutURL` | Hosted checkout URL for that variant |

The values are public identifiers and may safely ship in the app. Do not add a Lemon Squeezy API key, webhook secret, or other private credential to the Xcode project, source code, or app bundle.

## Test the customer flow

1. Install a build with the four values configured.
2. Purchase using a Lemon Squeezy test order or a real low-value test variant.
3. In MoleCube Settings, paste the emailed license key and click Activate.
4. Verify the license status changes to Pro.
5. Remove the license in MoleCube Settings, then confirm it can activate another Mac within the configured device limit.

The integration checks the returned Store, Product, and Variant IDs before accepting a response, so a valid Lemon Squeezy key from another product cannot unlock MoleCube Pro.
